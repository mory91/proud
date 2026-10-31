local diff = require("proud.diff")
local ui = require("proud.ui")
local keymap = require("proud.keymap")

local M = {}

local function pad(value, width, align_right)
  value = tostring(value or "")
  if #value >= width then
    return value:sub(1, width)
  end
  local padding = string.rep(" ", width - #value)
  return align_right and padding .. value or value .. padding
end

local function add_span(lines, highlights, line, needle, group)
  if not needle or needle == "" then
    return
  end
  local text = lines[line + 1] or ""
  local start_col = text:find(needle, 1, true)
  if start_col then
    table.insert(highlights, {
      line = line,
      start_col = start_col - 1,
      end_col = start_col - 1 + #needle,
      group = group,
    })
  end
end

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

function M.render_code(state)
  local lines = {}
  local highlights = {}
  local file = state.files[state.file_cursor]
  if not file then
    return {
      lines = { state.loading and "Loading diff..." or "No diff available" },
      highlights = {},
    }
  end
  table.insert(lines, ("main → %s"):format(state.pull.head_ref or "feature"))
  table.insert(lines, ("%s  [+%d -%d]  file %d / %d"):format(file.path, file.additions, file.deletions, state.file_cursor, #state.files))
  table.insert(lines, string.rep("─", 112))
  add_span(lines, highlights, 0, "main →", "ProudAccentText")
  add_span(lines, highlights, 0, state.pull.head_ref or "feature", "ProudAccentText")
  add_span(lines, highlights, 1, file.path, "ProudBright")
  add_span(lines, highlights, 1, "+" .. tostring(file.additions), "ProudSuccessText")
  add_span(lines, highlights, 1, "-" .. tostring(file.deletions), "ProudDangerText")
  add_span(lines, highlights, 2, string.rep("─", 24), "ProudMuted")

  local index = thread_index(state)
  for _, line in ipairs(diff.file_rows(file, state.sources[file.path])) do
    if line.kind == "context" or line.kind == "add" or line.kind == "delete" then
      local sign = line.kind == "add" and "+" or line.kind == "delete" and "-" or " "
      local line_number = line.new_line or line.old_line or 0
      local thread = index[file.path .. ":" .. tostring(line_number)]
      table.insert(lines, ("%4d %s %s %s"):format(line_number, thread and (thread.resolved and "◇" or "◆") or " ", sign, line.text))
      if line.kind == "add" then
        table.insert(highlights, { line = #lines - 1, start_col = 0, end_col = #lines[#lines], group = "ProudAdd" })
      elseif line.kind == "delete" then
        table.insert(highlights, { line = #lines - 1, start_col = 0, end_col = #lines[#lines], group = "ProudDelete" })
      end
      add_span(lines, highlights, #lines - 1, ("%4d "):format(line_number), "ProudMuted")
      if thread then
        add_span(lines, highlights, #lines - 1, thread.resolved and "◇" or "◆", thread.resolved and "ProudSuccessText" or "ProudWarning")
      end
    elseif line.kind == "hunk" and not state.sources[file.path] then
      table.insert(lines, "     " .. line.text)
    end
  end
  return { lines = lines, highlights = highlights }
end

function M.render_thread(state)
  local lines = {}
  local current_thread = state.threads[state.thread_cursor]
  table.insert(lines, "")
  if current_thread then
    table.insert(lines, ("%s  %s:%d  · %s · %d comments"):format(
      current_thread.resolved and "◇ resolved" or "◆ Thread",
      vim.fn.fnamemodify(current_thread.path, ":t"),
      current_thread.line,
      current_thread.resolved and "resolved" or "unresolved",
      #current_thread.comments
    ))
    for _, comment in ipairs(current_thread.comments) do
      table.insert(lines, comment.author .. "  " .. comment.age)
      table.insert(lines, "  " .. comment.body)
    end
  else
    table.insert(lines, "No review threads")
  end
  table.insert(lines, string.rep("─", 112))
  table.insert(lines, "Reply as you  · markdown  · @ mention")
  table.insert(lines, state.draft ~= "" and state.draft or "Write a reply...")
  table.insert(lines, "Draft ready  ·  resolve when the thread is complete")
  local highlights = {}
  if current_thread then
    add_span(lines, highlights, 1, current_thread.resolved and "◇ resolved" or "◆ Thread", current_thread.resolved and "ProudSuccessText" or "ProudWarning")
    add_span(lines, highlights, 1, vim.fn.fnamemodify(current_thread.path, ":t"), "ProudBright")
    add_span(lines, highlights, 1, current_thread.resolved and "resolved" or "unresolved", current_thread.resolved and "ProudSuccessText" or "ProudDangerText")
    local comment_line = 2
    for _, comment in ipairs(current_thread.comments) do
      add_span(lines, highlights, comment_line, comment.author, "ProudAccentText")
      add_span(lines, highlights, comment_line, comment.age, "ProudMuted")
      comment_line = comment_line + 2
    end
  else
    add_span(lines, highlights, 1, "No review threads", "ProudMuted")
  end
  add_span(lines, highlights, #lines - 4, string.rep("─", 18), "ProudMuted")
  add_span(lines, highlights, #lines - 3, "Reply as you", "ProudMuted")
  add_span(lines, highlights, #lines - 2, "Write a reply...", "ProudMuted")
  add_span(lines, highlights, #lines - 1, "Draft ready", "ProudAccentText")
  add_span(lines, highlights, #lines - 1, "resolve", "ProudSuccessText")
  return { lines = lines, highlights = highlights }
end

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
  return { lines = lines, highlights = code.highlights }
end

function M.render_files(state)
  local lines = { "Files  " .. #state.files }
  local highlights = {}
  for index, file in ipairs(state.files) do
    local marker = index == state.file_cursor and "▌" or " "
    table.insert(lines, ("%s%s %-28s +%d -%d"):format(
      marker,
      file.status or "M",
      vim.fn.fnamemodify(file.path, ":t"),
      file.additions,
      file.deletions
    ))
    if index == state.file_cursor then
      table.insert(highlights, { line = #lines - 1, start_col = 0, end_col = #"▌", group = "ProudAccent" })
    end
    local line = #lines - 1
    add_span(lines, highlights, line, file.status or "M", "ProudAccentText")
    add_span(lines, highlights, line, vim.fn.fnamemodify(file.path, ":t"), "ProudBright")
    add_span(lines, highlights, line, "+" .. tostring(file.additions), "ProudSuccessText")
    add_span(lines, highlights, line, "-" .. tostring(file.deletions), "ProudDangerText")
  end
  add_span(lines, highlights, 0, "Files", "ProudAccentText")
  return { lines = lines, highlights = highlights }
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
