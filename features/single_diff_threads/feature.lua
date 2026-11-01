local diff = require("proud.diff")
local ui = require("proud.ui")
local keymap = require("proud.keymap")

local M = {}

local function thread_index(state)
  local index = {}
  for _, thread in ipairs(state.threads) do
    index[thread.path .. ":" .. tostring(thread.line)] = thread
  end
  return index
end

function M.hydrate(state, data)
  data = data or {}
  if data.pull ~= nil then
    state.pull = require("proud.provider").normalize_pull_request(data.pull)
  end
  if data.threads ~= nil then
    state.threads = vim.deepcopy(data.threads or {})
  end
  if data.patch ~= nil then
    local selected_path = state.files[state.file_cursor] and state.files[state.file_cursor].path
    state.files = diff.parse_patch(data.patch or "")
    for index, file in ipairs(state.files) do
      if file.path == selected_path then
        state.file_cursor = index
        break
      end
    end
  end
  for path, source in pairs(data.sources or {}) do
    state.sources[path] = source
  end
  if data.patch ~= nil then
    state.loading = false
  end
  if state.refresh then
    state.refresh()
  end
  return state
end

function M.create(pull, threads, patch, sources)
  local state = {
    pull = require("proud.provider").normalize_pull_request(pull),
    threads = vim.deepcopy(threads or {}),
    files = diff.parse_patch(patch or (pull and pull.patch) or ""),
    sources = sources or {},
    file_cursor = 1,
    thread_cursor = 1,
    draft = "",
    loading = true,
  }
  if patch ~= nil then
    state.loading = false
  end
  return state
end

function M.add_reply(state, body)
  local thread = state.threads[state.thread_cursor]
  if not thread or not body or body == "" then
    return false
  end
  table.insert(thread.comments, {
    author = "you",
    age = "now",
    body = body,
  })
  state.draft = ""
  return true
end

function M.resolve(state)
  local thread = state.threads[state.thread_cursor]
  if not thread then
    return false
  end
  thread.resolved = true
  return true
end

function M.next_thread(state, delta)
  if #state.threads == 0 then
    return
  end
  state.thread_cursor = (state.thread_cursor - 1 + delta) % #state.threads + 1
end

-- Rule width when no pane width is known (tests, benchmarks).
local DEFAULT_RULE_WIDTH = 112

-- A separator `width` cells wide whose first `head` cells are muted.
local function add_rule(v, width, head)
  width = math.max(1, math.floor(width or DEFAULT_RULE_WIDTH))
  head = math.min(head, width)
  v:spans(string.rep("─", head), "ProudMuted", string.rep("─", width - head))
end

-- Diff rows use spans() and fill(): this renderer is on the diff SLA path
-- (1,200 rows), so it avoids per-row chunk tables.
-- Gutter: old and new line numbers, right-aligned, then the sign column.
local GUTTER_WIDTH = 10
M.gutter_width = GUTTER_WIDTH
local PREVIEW_CHARS = 32

local function number_text(value)
  return value and tostring(value) or ""
end

-- First comment of an open thread, shortened for the end-of-line preview.
local function thread_preview(thread)
  if thread.resolved then
    return "   ◇ resolved"
  end
  local first = (thread.comments or {})[1]
  if not first then
    return "   ◆ thread"
  end
  local body = tostring(first.body or ""):gsub("%s+", " ")
  if not body:find("[\128-\255]") then
    -- ASCII: byte length is the character count, no Vimscript calls.
    if #body > PREVIEW_CHARS then
      body = body:sub(1, PREVIEW_CHARS - 1) .. "…"
    end
  elseif vim.fn.strchars(body) > PREVIEW_CHARS then
    body = vim.fn.strcharpart(body, 0, PREVIEW_CHARS - 1) .. "…"
  end
  return ("   ◆ %s: %s"):format(first.author or "unknown", body)
end

-- The selected file's full text with deleted rows inserted. Records each
-- thread's row in state.thread_rows for cursor navigation.
function M.render_code(state)
  local v = ui.view.new()
  state.thread_rows = {}
  local file = state.files[state.file_cursor]
  if not file then
    v:spans(state.loading and "Loading diff..." or "No diff available")
    return v:build()
  end
  local index = thread_index(state)
  local seg = v:segments()
  for _, line in ipairs(diff.file_rows(file, state.sources[file.path])) do
    local kind = line.kind
    if kind == "context" or kind == "add" or kind == "delete" then
      local thread = index[file.path .. ":" .. tostring(line.new_line or line.old_line or 0)]
      local sign, sign_group = " ", false
      if thread then
        sign, sign_group = thread.resolved and "◇" or "◆", "ProudWarning"
      elseif kind == "add" then
        sign, sign_group = "+", "ProudSuccess"
      elseif kind == "delete" then
        sign, sign_group = "-", "ProudDanger"
      end
      seg[1], seg[2] = ("%4s %4s "):format(number_text(line.old_line), number_text(line.new_line)), "ProudMuted"
      seg[3], seg[4] = sign, sign_group
      seg[5], seg[6] = " " .. line.text, false
      local row = v:emit(seg, 6, kind == "add" and "ProudAdd" or kind == "delete" and "ProudDelete" or nil)
      if thread then
        state.thread_rows[thread] = row
        v:eol(row, thread_preview(thread), "ProudMuted")
      end
    elseif kind == "hunk" and not state.sources[file.path] then
      v:spans("           " .. line.text, "ProudMuted")
    end
  end
  return v:build()
end

-- Window bar: base → head, path, change counts and file position.
function M.winbar(state)
  local pull = state.pull
  local segments = {
    { pull.base_ref or "main", "ProudAccentText" },
    { " → ", "ProudMuted" },
    { pull.head_ref or "feature", "ProudSuccessText" },
  }
  local file = state.files[state.file_cursor]
  if not file then
    segments[#segments + 1] = { state.loading and "   loading…" or "   no diff", "ProudMuted" }
    return segments
  end
  segments[#segments + 1] = { "   " .. file.path .. "   ", "ProudMuted" }
  segments[#segments + 1] = { ("[+%d −%d]"):format(file.additions or 0, file.deletions or 0), "ProudAccentText" }
  segments[#segments + 1] = { ("   %d / %d"):format(state.file_cursor, #state.files), "ProudMuted" }
  return segments
end

function M.render_thread(state, width)
  local v = ui.view.new()
  local current_thread = state.threads[state.thread_cursor]
  v:blank()
  if current_thread then
    local resolved = current_thread.resolved
    v:spans(
      resolved and "◇ resolved" or "◆ Thread", resolved and "ProudSuccessText" or "ProudWarning",
      "  ", nil,
      vim.fn.fnamemodify(current_thread.path, ":t"), "ProudBright",
      ":" .. current_thread.line .. "  · ", nil,
      resolved and "resolved" or "unresolved", resolved and "ProudSuccessText" or "ProudDangerText",
      (" · %d comments"):format(#current_thread.comments)
    )
    for _, comment in ipairs(current_thread.comments) do
      v:spans(comment.author, "ProudAccentText", "  ", nil, comment.age, "ProudMuted")
      v:spans("  " .. comment.body)
    end
  else
    v:spans("No review threads", "ProudMuted")
  end
  add_rule(v, width, 18)
  v:spans("Reply as you", "ProudMuted", "  · markdown  · @ mention")
  if state.draft ~= "" then
    v:spans(state.draft)
  else
    v:spans("Write a reply...", "ProudMuted")
  end
  v:spans("Draft ready", "ProudAccentText", "  ·  ", nil, "resolve", "ProudSuccessText", " when the thread is complete")
  return v:build()
end

-- Code lines followed by thread lines; only the code rows are highlighted.
function M.render(state)
  local code = M.render_code(state)
  local thread = M.render_thread(state)
  local lines = {}
  for _, line in ipairs(code.lines) do
    table.insert(lines, line)
  end
  for _, line in ipairs(thread.lines) do
    table.insert(lines, line)
  end
  return { lines = lines, highlights = code.highlights, highlight_format = code.highlight_format }
end

function M.render_panes(state)
  return { code = M.render_code(state) }
end

local cursor_namespace = vim.api.nvim_create_namespace("proud_diff_cursor")

-- Bold, bright line numbers on the cursor row (CursorLine colors the row).
local function mark_cursor_row(buffer, window)
  if not vim.api.nvim_buf_is_valid(buffer) or not vim.api.nvim_win_is_valid(window) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buffer, cursor_namespace, 0, -1)
  local row = vim.api.nvim_win_get_cursor(window)[1] - 1
  local line = vim.api.nvim_buf_get_lines(buffer, row, row + 1, false)[1] or ""
  if #line >= GUTTER_WIDTH then
    vim.api.nvim_buf_set_extmark(buffer, cursor_namespace, row, 0, {
      end_col = GUTTER_WIDTH,
      hl_group = "ProudBright",
      priority = 4200,
    })
  end
end

local function file_index(state, path)
  for index, file in ipairs(state.files) do
    if file.path == path then
      return index
    end
  end
end

function M.attach(buffer, state, options)
  options = options or {}
  local workspace = options.workspace
  local window = ui.workspace_window(workspace, "code")
  local function ensure_source()
    local file = state.files[state.file_cursor]
    if file and state.sources[file.path] == nil and options.load_source then
      state.sources[file.path] = options.load_source(file.path) or false
    end
  end
  local function refresh()
    ensure_source()
    ui.render_workspace(workspace, M.render_panes(state))
    ui.winbar(window, M.winbar(state))
    mark_cursor_row(buffer, window)
  end
  local function select_file(file_cursor)
    if not state.files[file_cursor] then
      return
    end
    state.file_cursor = file_cursor
    refresh()
    ui.set_cursor(buffer, 1, 0)
  end
  -- Selects a thread, switching to its file, and puts the cursor on its row.
  local function show_thread(delta)
    M.next_thread(state, delta)
    local thread = state.threads[state.thread_cursor]
    if not thread then
      return
    end
    local target = file_index(state, thread.path)
    if target and target ~= state.file_cursor then
      state.file_cursor = target
    end
    refresh()
    local row = state.thread_rows and state.thread_rows[thread]
    if row then
      ui.set_cursor(buffer, row + 1, GUTTER_WIDTH)
    end
  end
  state.refresh = refresh
  keymap.map_workspace(workspace, "n", "next_file", function()
    select_file(state.file_cursor % #state.files + 1)
  end, "Next file")
  keymap.map_workspace(workspace, "n", "previous_file", function()
    select_file((state.file_cursor - 2) % #state.files + 1)
  end, "Previous file")
  keymap.map_workspace(workspace, "n", "next_thread", function()
    show_thread(1)
  end, "Next thread")
  keymap.map_workspace(workspace, "n", "previous_thread", function()
    show_thread(-1)
  end, "Previous thread")
  keymap.map_workspace(workspace, "n", "reply", function()
    local body = vim.fn.input("Reply: ", state.draft)
    if body ~= "" then
      M.add_reply(state, body)
      refresh()
    end
  end, "Reply to thread")
  keymap.map_workspace(workspace, "n", "resolve", function()
    M.resolve(state)
    refresh()
  end, "Resolve thread")
  keymap.bind_common_workspace(workspace, {
    on_quit = options.on_quit or function()
      ui.close_workspace(workspace)
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = workspace.lifecycle.group,
    buffer = buffer,
    callback = function()
      mark_cursor_row(buffer, window)
    end,
  })
  refresh()
end

function M.title(state)
  return "#" .. tostring(state.pull.number) .. " diff · single-pane"
end

function M.open(state, options)
  local name = "proud://pr/" .. tostring(state.pull.number) .. "/diff/single"
  local workspace = ui.open_workspace(name, {
    {
      name = "code",
      buffer_name = name .. "/code",
      title = M.title(state),
      view = M.render_code(state),
      weight = 1,
    },
  }, {
    focus = "code",
    title = M.title(state),
    statusline = M.title(state),
    on_resize = function()
      if state.refresh then
        state.refresh()
      end
    end,
  })
  state.workspace = workspace
  local buffer = ui.workspace_buffer(workspace, "code")
  M.attach(buffer, state, vim.tbl_extend("force", options or {}, { workspace = workspace }))
  return buffer
end

return M
