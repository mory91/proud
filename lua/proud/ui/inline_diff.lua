-- Live inline diff on a real, editable buffer. The buffer's current text
-- is compared with a base text using Neovim's built-in xdiff (vim.diff):
--   - added and changed lines get a background-only line highlight and a
--     "+" sign, so the code keeps its syntax colors
--   - deleted lines are drawn as virtual lines at their old position, with
--     the base text's treesitter colors over the delete background
-- Decorations are recomputed (debounced) whenever the buffer changes, so
-- editing updates the diff as you type. Line numbers, signs and syntax
-- come from Neovim itself; nothing is drawn into the buffer text.
local ui_text = require("proud.ui.text")

local M = {}

M.namespace = vim.api.nvim_create_namespace("proud_inline_diff")
local namespace = M.namespace

M.groups = {
  add = "ProudAddLine",
  delete = "ProudDeleteLine",
  add_sign = "ProudSuccess",
}

local diff_function = (vim.text and vim.text.diff) or vim.diff

local function buffer_text(buffer)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  return table.concat(lines, "\n") .. "\n", lines
end

local function as_text(base)
  if type(base) == "table" then
    base = table.concat(base, "\n")
  end
  base = tostring(base or "")
  if base ~= "" and base:sub(-1) ~= "\n" then
    base = base .. "\n"
  end
  return base
end

-- Widest window showing `buffer`, so deleted lines fill the whole row.
local function row_width(buffer)
  local width = 80
  for _, window in ipairs(vim.fn.win_findbuf(buffer)) do
    width = math.max(width, vim.api.nvim_win_get_width(window))
  end
  return width
end

-- Hunks between base and the buffer: { { start_a, count_a, start_b, count_b } }
-- Myers with git's indent heuristic: git's default. (histogram measured up
-- to 20x slower on long runs of alternating changes.)
local diff_options = { result_type = "indices", algorithm = "myers", indent_heuristic = true }
function M.hunks(base, current)
  return diff_function(base, current, diff_options)
end

local padding_cache = {}
local function padding(count)
  local value = padding_cache[count]
  if not value then
    value = string.rep(" ", count)
    padding_cache[count] = value
  end
  return value
end

-- Treesitter colors of a base text, for drawing its deleted lines.
-- Returns a syntax object, or nil when `lang` has no parser or highlights
-- query. Parsing is asynchronous (M.parse); captures are read per deleted
-- row only when that row is about to be seen, and cached with the drawn
-- chunks, so edits and scrolling reuse them.
function M.syntax(text, lang)
  if not lang or not text or text == "" then
    return nil
  end
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, lang)
  if not ok or not parser then
    return nil
  end
  local found, query = pcall(vim.treesitter.query.get, lang, "highlights")
  if not found or not query then
    return nil
  end
  return { text = text, lang = lang, parser = parser, query = query, groups = {}, captures = {}, rows = {} }
end

-- Parses the base; `callback(syntax)` once its tree is ready. Synchronous
-- when `sync` is set.
function M.parse(syntax, callback, sync)
  local function done(trees)
    if trees and trees[1] then
      syntax.tree = trees[1]
      if callback then
        callback(syntax)
      end
    end
  end
  if sync then
    local ok, trees = pcall(syntax.parser.parse, syntax.parser)
    return done(ok and trees or nil)
  end
  local ok = pcall(syntax.parser.parse, syntax.parser, true, function(err, trees)
    if not err then
      done(trees)
    end
  end)
  if not ok then
    done(nil)
  end
end

-- Captures of base rows first..last (1-based), cached per row as
-- { start_col, end_col, { delete_group, capture_group } }.
local function read_captures(syntax, first, last)
  local captures = syntax.captures
  local missing = false
  for index = first, last do
    if not captures[index] then
      missing = true
      captures[index] = {}
    end
  end
  if not missing then
    return
  end
  local query, groups, lang = syntax.query, syntax.groups, syntax.lang
  for id, node in query:iter_captures(syntax.tree:root(), syntax.text, first - 1, last) do
    local name = query.captures[id]
    if name:byte(1) ~= 95 and name ~= "spell" and name ~= "nospell" and name ~= "conceal" then
      local group = groups[id]
      if not group then
        group = { M.groups.delete, "@" .. name .. "." .. lang }
        groups[id] = group
      end
      local start_row, start_col, end_row, end_col = node:range()
      for row = math.max(start_row, first - 1), math.min(end_row, last - 1) do
        local from = row == start_row and start_col or 0
        local to = row == end_row and end_col or math.huge
        if to > from then
          local list = captures[row + 1]
          list[#list + 1] = { from, to, group }
        end
      end
    end
  end
end

-- One deleted line as virtual-line chunks: syntax colors stacked over the
-- delete background, tabs expanded, padded to `width`.
local function deleted_row(text, captures, tab, width)
  local chunks = {}
  if captures and #text > 0 then
    -- Later captures are more specific and win, as in Neovim's highlighter.
    local paint = {}
    local length = #text
    for _, capture in ipairs(captures) do
      for column = capture[1] + 1, math.min(capture[2], length) do
        paint[column] = capture[3]
      end
    end
    local start = 1
    for column = 2, length + 1 do
      if column > length or paint[column] ~= paint[start] then
        chunks[#chunks + 1] = { text:sub(start, column - 1), paint[start] or M.groups.delete }
        start = column
      end
    end
  else
    chunks[1] = { text, M.groups.delete }
  end
  local shown = 0
  for _, chunk in ipairs(chunks) do
    if chunk[1]:find("\t", 1, true) then
      chunk[1] = chunk[1]:gsub("\t", tab)
    end
    shown = shown + ui_text.display_width(chunk[1])
  end
  -- A cached padding chunk fills the row with the delete background
  -- without building a new padded string.
  if width - shown > 0 then
    chunks[#chunks + 1] = { padding(width - shown), M.groups.delete }
  end
  return chunks
end

-- A deleted row's colored chunks, built once per width and tabstop.
local function colored_row(syntax, index, text, tab, width)
  local cached = syntax.rows[index]
  if not cached or cached.width ~= width or cached.tab ~= tab then
    cached = { width = width, tab = tab, chunks = deleted_row(text, syntax.captures[index], tab, width) }
    syntax.rows[index] = cached
  end
  return cached.chunks
end

-- Replaces the buffer's decorations; returns stats { added, deleted,
-- hunks } and the deleted-line marks { id, row, above, first, count,
-- width, tab, colored }. With a parsed `syntax` (M.syntax), deleted rows
-- that were colored before are drawn colored; the rest are plain until
-- M.color() reaches them.
function M.decorate(buffer, base_text, base_lines, tabstop, syntax)
  local current, lines = buffer_text(buffer)
  vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
  local stats = { added = 0, deleted = 0, hunks = 0 }
  local marks = {}
  if base_text == current then
    return stats, marks
  end
  local width = row_width(buffer)
  local tab = string.rep(" ", tabstop or 8)
  local line_count = #lines
  local rows = syntax and syntax.tree and syntax.rows
  for _, hunk in ipairs(M.hunks(base_text, current)) do
    local start_a, count_a, start_b, count_b = hunk[1], hunk[2], hunk[3], hunk[4]
    stats.hunks = stats.hunks + 1
    for line = start_b, start_b + count_b - 1 do
      vim.api.nvim_buf_set_extmark(buffer, namespace, line - 1, 0, {
        line_hl_group = M.groups.add,
        sign_text = "+",
        sign_hl_group = M.groups.add_sign,
        priority = 100,
      })
    end
    stats.added = stats.added + count_b
    if count_a > 0 then
      local virtual = {}
      local colored = rows ~= nil
      for index = start_a, start_a + count_a - 1 do
        local cached = rows and rows[index]
        if cached and cached.width == width and cached.tab == tab then
          virtual[#virtual + 1] = cached.chunks
        else
          colored = false
          virtual[#virtual + 1] = deleted_row(base_lines[index] or "", nil, tab, width)
        end
      end
      stats.deleted = stats.deleted + count_a
      -- Changed lines: old text above the new. Pure deletions: below the
      -- line they followed (start_b), or above the first line.
      local row, above
      if count_b > 0 then
        row, above = start_b - 1, true
      elseif start_b == 0 then
        row, above = 0, true
      else
        row, above = math.min(start_b, line_count) - 1, false
      end
      if line_count == 0 then
        row, above = 0, false
      end
      row = math.max(0, row)
      local id = vim.api.nvim_buf_set_extmark(buffer, namespace, row, 0, {
        virt_lines = virtual,
        virt_lines_above = above,
        priority = 100,
      })
      marks[#marks + 1] = { id = id, row = row, above = above, first = start_a, count = count_a, width = width, tab = tab, colored = colored }
    end
  end
  return stats, marks
end

-- Buffer rows shown in windows, with a window height of margin each way.
local function visible_rows(buffer)
  local ranges = {}
  for _, window in ipairs(vim.fn.win_findbuf(buffer)) do
    local top = vim.fn.line("w0", window) - 1
    local bottom = vim.fn.line("w$", window) - 1
    local margin = vim.api.nvim_win_get_height(window)
    ranges[#ranges + 1] = { top - margin, bottom + margin }
  end
  return ranges
end

-- Colors the deleted lines of `marks` that are in view (or all of them
-- with `all`), using a parsed `syntax`. Returns how many marks it colored.
function M.color(buffer, base_lines, syntax, marks, all)
  if not (syntax and syntax.tree) or not vim.api.nvim_buf_is_valid(buffer) then
    return 0
  end
  local ranges = not all and visible_rows(buffer) or nil
  local count = 0
  for _, mark in ipairs(marks) do
    local wanted = not mark.colored
    if wanted and ranges then
      wanted = false
      for _, range in ipairs(ranges) do
        if mark.row >= range[1] and mark.row <= range[2] then
          wanted = true
          break
        end
      end
    end
    if wanted then
      local last = mark.first + mark.count - 1
      read_captures(syntax, mark.first, last)
      local virtual = {}
      for index = mark.first, last do
        virtual[#virtual + 1] = colored_row(syntax, index, base_lines[index] or "", mark.tab, mark.width)
      end
      pcall(vim.api.nvim_buf_set_extmark, buffer, namespace, mark.row, 0, {
        id = mark.id,
        virt_lines = virtual,
        virt_lines_above = mark.above,
        priority = 100,
      })
      mark.colored = true
      count = count + 1
    end
  end
  return count
end

-- Attaches a live inline diff to `buffer`.
-- options: base (string or lines), delay_ms (default 40),
--          on_update(stats) after every recompute.
-- Returns a handle: refresh(), set_base(base), detach(), stats.
function M.attach(buffer, options)
  options = options or {}
  local handle = { buffer = buffer, stats = { added = 0, deleted = 0, hunks = 0 } }
  local base_text, base_lines
  -- The base's colors: parsed asynchronously once per base and filetype.
  local syntax, syntax_lang
  local marks = {}
  local function set_base(base)
    base_text = as_text(base)
    base_lines = vim.split(base_text:gsub("\n$", ""), "\n", { plain = true })
    if base_text == "" then
      base_lines = {}
    end
    syntax, syntax_lang = nil, nil
  end
  set_base(options.base)

  local function color_visible()
    if syntax and #marks > 0 then
      M.color(buffer, base_lines, syntax, marks)
    end
  end

  local function base_syntax()
    local filetype = vim.bo[buffer].filetype
    local lang = filetype ~= "" and vim.treesitter.language.get_lang(filetype) or nil
    if lang ~= syntax_lang then
      syntax_lang = lang
      syntax = M.syntax(base_text, lang) or false
      local parsing = syntax
      if parsing then
        M.parse(parsing, function()
          if syntax == parsing then
            color_visible()
          end
        end)
      end
    end
    return syntax or nil
  end

  function handle.refresh()
    if not vim.api.nvim_buf_is_valid(buffer) then
      return
    end
    handle.stats, marks = M.decorate(buffer, base_text, base_lines, vim.bo[buffer].tabstop, base_syntax())
    color_visible()
    if options.on_update then
      options.on_update(handle.stats)
    end
  end

  -- Colors every deleted line now (tests and callers that need it).
  function handle.color_all()
    if syntax and syntax.tree then
      M.color(buffer, base_lines, syntax, marks, true)
    end
  end

  function handle.syntax()
    return syntax or nil
  end

  function handle.set_base(base)
    set_base(base)
    handle.refresh()
  end

  local timer = (vim.uv or vim.loop).new_timer()
  local group = vim.api.nvim_create_augroup("ProudInlineDiff" .. buffer, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
    group = group,
    buffer = buffer,
    callback = function()
      timer:stop()
      timer:start(options.delay_ms or 40, 0, vim.schedule_wrap(handle.refresh))
    end,
  })
  -- Deleted lines are colored as they scroll into view.
  vim.api.nvim_create_autocmd({ "WinScrolled", "BufWinEnter" }, {
    group = group,
    callback = function()
      if vim.api.nvim_buf_is_valid(buffer) and vim.fn.bufwinid(buffer) ~= -1 then
        color_visible()
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWipeout" }, {
    group = group,
    buffer = buffer,
    callback = function()
      handle.detach()
    end,
  })

  function handle.detach()
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    pcall(vim.api.nvim_del_augroup_by_id, group)
    if vim.api.nvim_buf_is_valid(buffer) then
      vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
    end
  end

  handle.refresh()
  return handle
end

return M
