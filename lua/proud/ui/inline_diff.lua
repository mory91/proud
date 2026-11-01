-- Live inline diff on a real, editable buffer. The buffer's current text
-- is compared with a base text using Neovim's built-in xdiff (vim.diff):
--   - added and changed lines get a line highlight and a "+" sign
--   - deleted lines are drawn as virtual lines at their old position
-- Decorations are recomputed (debounced) whenever the buffer changes, so
-- editing updates the diff as you type. Line numbers, signs and syntax
-- come from Neovim itself; nothing is drawn into the buffer text.
local ui_text = require("proud.ui.text")

local M = {}

M.namespace = vim.api.nvim_create_namespace("proud_inline_diff")
local namespace = M.namespace

M.groups = {
  add = "ProudAdd",
  delete = "ProudDelete",
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

-- Replaces the buffer's decorations; returns { added = n, deleted = n }.
function M.decorate(buffer, base_text, base_lines, tabstop)
  local current, lines = buffer_text(buffer)
  vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
  local stats = { added = 0, deleted = 0, hunks = 0 }
  if base_text == current then
    return stats
  end
  local width = row_width(buffer)
  local tab = string.rep(" ", tabstop or 8)
  local line_count = #lines
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
      for index = start_a, start_a + count_a - 1 do
        local text = base_lines[index] or ""
        if text:find("\t", 1, true) then
          text = text:gsub("\t", tab)
        end
        local pad = width - ui_text.display_width(text)
        -- Two chunks (text, then cached padding) fill the row with the
        -- delete background without building a new padded string.
        virtual[#virtual + 1] = pad > 0
          and { { text, M.groups.delete }, { padding(pad), M.groups.delete } }
          or { { text, M.groups.delete } }
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
      vim.api.nvim_buf_set_extmark(buffer, namespace, math.max(0, row), 0, {
        virt_lines = virtual,
        virt_lines_above = above,
        priority = 100,
      })
    end
  end
  return stats
end

-- Attaches a live inline diff to `buffer`.
-- options: base (string or lines), delay_ms (default 40),
--          on_update(stats) after every recompute.
-- Returns a handle: refresh(), set_base(base), detach(), stats.
function M.attach(buffer, options)
  options = options or {}
  local handle = { buffer = buffer, stats = { added = 0, deleted = 0, hunks = 0 } }
  local base_text, base_lines
  local function set_base(base)
    base_text = as_text(base)
    base_lines = vim.split(base_text:gsub("\n$", ""), "\n", { plain = true })
    if base_text == "" then
      base_lines = {}
    end
  end
  set_base(options.base)

  function handle.refresh()
    if not vim.api.nvim_buf_is_valid(buffer) then
      return
    end
    handle.stats = M.decorate(buffer, base_text, base_lines, vim.bo[buffer].tabstop)
    if options.on_update then
      options.on_update(handle.stats)
    end
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
