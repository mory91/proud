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

local RULE_112 = string.rep("─", 112)
local RULE_HEAD_24 = string.rep("─", 24)
local RULE_TAIL_88 = string.rep("─", 112 - 24)
local RULE_HEAD_18 = string.rep("─", 18)
local RULE_TAIL_94 = string.rep("─", 112 - 18)

-- Diff rows use spans() and fill(): this renderer is on the diff SLA path
-- (1,200 rows), so it avoids per-row chunk tables.
function M.render_code(state)
  local v = ui.view.new()
  local file = state.files[state.file_cursor]
  if not file then
    v:spans(state.loading and "Loading diff..." or "No diff available")
    return v:build()
  end
  v:spans("main →", "ProudAccentText", " ", nil, state.pull.head_ref or "feature", "ProudAccentText")
  v:spans(
    file.path, "ProudBright",
    "  [", nil,
    "+" .. tostring(file.additions), "ProudSuccessText",
    " ", nil,
    "-" .. tostring(file.deletions), "ProudDangerText",
    ("]  file %d / %d"):format(state.file_cursor, #state.files)
  )
  v:spans(RULE_HEAD_24, "ProudMuted", RULE_TAIL_88)

  local index = thread_index(state)
  for _, line in ipairs(diff.file_rows(file, state.sources[file.path])) do
    local kind = line.kind
    if kind == "context" or kind == "add" or kind == "delete" then
      local sign = kind == "add" and "+" or kind == "delete" and "-" or " "
      local line_number = line.new_line or line.old_line or 0
      local thread = index[file.path .. ":" .. tostring(line_number)]
      v:open()
      if kind == "add" then
        v:fill("ProudAdd")
      elseif kind == "delete" then
        v:fill("ProudDelete")
      end
      v:add(("%4d "):format(line_number), "ProudMuted")
      if thread then
        v:add(thread.resolved and "◇" or "◆", thread.resolved and "ProudSuccessText" or "ProudWarning")
      else
        v:add(" ")
      end
      v:add(" " .. sign .. " " .. line.text)
      v:close()
    elseif kind == "hunk" and not state.sources[file.path] then
      v:spans("     " .. line.text)
    end
  end
  return v:build()
end

function M.render_thread(state)
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
  v:spans(RULE_HEAD_18, "ProudMuted", RULE_TAIL_94)
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

-- Byte padding, matching string.format's %-Ns columns.
local function pad(value, width)
  return string.rep(" ", math.max(0, width - #value))
end

function M.render_files(state)
  local v = ui.view.new()
  v:spans("Files", "ProudAccentText", "  " .. #state.files)
  for index, file in ipairs(state.files) do
    local name = vim.fn.fnamemodify(file.path, ":t")
    v:open()
    if index == state.file_cursor then
      v:add("▌", "ProudAccent")
    else
      v:add(" ")
    end
    v:add(file.status or "M", "ProudAccentText")
      :add(" ")
      :add(name, "ProudBright")
      :add(pad(name, 28) .. " ")
      :add("+" .. tostring(file.additions), "ProudSuccessText")
      :add(" ")
      :add("-" .. tostring(file.deletions), "ProudDangerText")
    v:close()
  end
  return v:build()
end

function M.render_panes(state)
  return {
    files = M.render_files(state),
    code = M.render_code(state),
    thread = M.render_thread(state),
  }
end

function M.attach(buffer, state, options)
  options = options or {}
  local function ensure_source()
    local file = state.files[state.file_cursor]
    if file and state.sources[file.path] == nil and options.load_source then
      state.sources[file.path] = options.load_source(file.path) or false
    end
  end
  local function refresh()
    ensure_source()
    ui.render_workspace(options.workspace, M.render_panes(state))
  end
  local function select_file(file_cursor)
    if not state.files[file_cursor] then
      return
    end
    state.file_cursor = file_cursor
    refresh()
    ui.set_cursor(buffer, file_cursor + 1, 0)
  end
  state.refresh = refresh
  keymap.map_workspace(options.workspace, "n", "next_file", function()
    select_file(state.file_cursor % #state.files + 1)
  end, "Next file")
  keymap.map_workspace(options.workspace, "n", "previous_file", function()
    select_file((state.file_cursor - 2) % #state.files + 1)
  end, "Previous file")
  keymap.map(buffer, "n", "select_file", function()
    select_file(vim.api.nvim_win_get_cursor(0)[1] - 1)
  end, "Open focused diff file")
  keymap.map_workspace(options.workspace, "n", "next_thread", function()
    M.next_thread(state, 1)
    refresh()
  end, "Next thread")
  keymap.map_workspace(options.workspace, "n", "previous_thread", function()
    M.next_thread(state, -1)
    refresh()
  end, "Previous thread")
  keymap.map_workspace(options.workspace, "n", "reply", function()
    local body = vim.fn.input("Reply: ", state.draft)
    if body ~= "" then
      M.add_reply(state, body)
      refresh()
    end
  end, "Reply to thread")
  keymap.map_workspace(options.workspace, "n", "resolve", function()
    M.resolve(state)
    refresh()
  end, "Resolve thread")
  keymap.bind_common_workspace(options.workspace, {
    on_quit = options.on_quit or function()
      ui.close_workspace(options.workspace)
    end,
  })
  refresh()
end

function M.open(state, options)
  local name = "proud://pr/" .. tostring(state.pull.number) .. "/diff/single"
  local panes = M.render_panes(state)
  local workspace = ui.open_workspace(name, {
    {
      name = "files",
      buffer_name = name .. "/files",
      title = "#" .. tostring(state.pull.number) .. " diff · single",
      view = panes.files,
      weight = 0.22,
    },
    {
      name = "code",
      buffer_name = name .. "/code",
      title = "#" .. tostring(state.pull.number) .. " diff · single",
      view = panes.code,
      weight = 0.48,
    },
    {
      name = "thread",
      buffer_name = name .. "/thread",
      title = "#" .. tostring(state.pull.number) .. " diff · single",
      view = panes.thread,
      weight = 0.30,
    },
  }, {
    focus = "files",
    title = "#" .. tostring(state.pull.number) .. " diff · single",
    statusline = "#" .. tostring(state.pull.number) .. " diff · single",
    on_resize = function()
      if state.refresh then
        state.refresh()
      end
    end,
  })
  state.workspace = workspace
  local buffer = ui.workspace_buffer(workspace, "files")
  M.attach(buffer, state, vim.tbl_extend("force", options or {}, { workspace = workspace }))
  return buffer
end

return M
