-- Diff pane: one changed file at a time, inside a window owned by a host
-- page (the compare page). Two sources:
--
--   worktree  the real file in a normal, editable buffer, compared live
--             with a base revision (the merge base). Edits re-diff as you
--             type and saving writes the file. Review threads show as
--             signs and end-of-line previews that move with the text.
--   commit    one commit's version of the file (read-only), compared with
--             the same file in the commit's parent: "the change of that
--             commit".
--
-- Line numbers, signs and syntax are Neovim's own; ui.inline_diff draws
-- added lines as highlights and deleted lines as virtual lines.
local git = require("proud.git")
local ui = require("proud.ui")
local keymap = require("proud.keymap")

local M = {}

M.thread_namespace = vim.api.nvim_create_namespace("proud_diff_threads")
local PREVIEW_CHARS = 32
local FILE_ACTIONS = { "next_file", "previous_file", "next_thread", "previous_thread" }

-- options: cwd, threads, title (e.g. "#482" or "main...feature", used in
-- status messages).
function M.create(options)
  options = options or {}
  return {
    cwd = options.cwd,
    title = options.title or "",
    threads = vim.deepcopy(options.threads or {}),
    files = {},
    file_cursor = 1,
    thread_cursor = 1,
    draft = "",
    status = "loading",
    message = options.message,
    label = {},
    source = nil,
  }
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

-- Text view of the selected thread (kept for the thread window, #40).
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

-- First comment of an open thread, shortened for the end-of-line preview.
function M.thread_preview(thread)
  if thread.resolved then
    return "   ◇ resolved"
  end
  local first = (thread.comments or {})[1]
  if not first then
    return "   ◆ thread"
  end
  local body = tostring(first.body or ""):gsub("%s+", " ")
  if not body:find("[\128-\255]") then
    if #body > PREVIEW_CHARS then
      body = body:sub(1, PREVIEW_CHARS - 1) .. "…"
    end
  elseif vim.fn.strchars(body) > PREVIEW_CHARS then
    body = vim.fn.strcharpart(body, 0, PREVIEW_CHARS - 1) .. "…"
  end
  return ("   ◆ %s: %s"):format(first.author or "unknown", body)
end

-- Window bar: the host's label (e.g. main...feature, or a commit), then
-- path, live change counts and the file's position.
function M.winbar(state, stats)
  local segments = {}
  for _, segment in ipairs(state.label or {}) do
    segments[#segments + 1] = segment
  end
  local file = state.files[state.file_cursor]
  if state.status ~= "ready" or not file then
    local label = state.status == "error" and "   could not open the diff"
      or state.status == "empty" and "   no changes"
      or "   loading…"
    segments[#segments + 1] = { label, state.status == "error" and "ProudDangerText" or "ProudMuted" }
    return segments
  end
  stats = stats or {}
  segments[#segments + 1] = { "   " .. file.path .. "   ", "ProudMuted" }
  segments[#segments + 1] = { ("[+%d −%d]"):format(stats.added or 0, stats.deleted or 0), "ProudAccentText" }
  segments[#segments + 1] = { ("   %d / %d"):format(state.file_cursor, #state.files), "ProudMuted" }
  return segments
end

-- The pane's status buffer while loading, on error, or with no changes.
function M.status_view(state)
  local v = ui.view.new()
  if state.status == "error" then
    v:line({ "Could not open the diff for " .. state.title, "ProudDangerText" })
    v:blank()
    for _, line in ipairs(vim.split(state.error or "", "\n", { plain = true })) do
      v:line(line)
    end
  elseif state.status == "empty" then
    v:line({ "No changes", "ProudMuted" }, " in ", { state.title, "ProudAccentText" })
  else
    v:line({ state.message or "Loading…", "ProudMuted" })
  end
  return v:build()
end

local function alive(state)
  local scene = state.scene
  return scene ~= nil and not scene.detached and vim.api.nvim_win_is_valid(scene.window)
end
M.alive = alive

local function current_buffer(state)
  return vim.api.nvim_win_get_buf(state.scene.window)
end

-- Signs and end-of-line previews for the current file's threads (worktree
-- only: threads belong to the pull request's head). Records each thread's
-- extmark so navigation follows edits.
function M.place_threads(state, buffer, file)
  vim.api.nvim_buf_clear_namespace(buffer, M.thread_namespace, 0, -1)
  state.thread_marks = {}
  if state.source and state.source.kind ~= "worktree" then
    return
  end
  local line_count = vim.api.nvim_buf_line_count(buffer)
  for _, thread in ipairs(state.threads) do
    if thread.path == file.path and thread.line and thread.line >= 1 and thread.line <= line_count then
      state.thread_marks[thread] = vim.api.nvim_buf_set_extmark(buffer, M.thread_namespace, thread.line - 1, 0, {
        sign_text = thread.resolved and "◇" or "◆",
        sign_hl_group = "ProudWarning",
        virt_text = { { M.thread_preview(thread), "ProudMuted" } },
        virt_text_pos = "eol",
        priority = 200,
      })
    end
  end
end

local function unmap_actions(buffer, actions)
  for _, action in ipairs(actions or {}) do
    keymap.unmap(buffer, "n", action)
  end
end

-- Detaches the diff, thread marks and mappings from `buffer`.
local function release_buffer(state, buffer)
  local scene = state.scene
  local handle = scene.handles[buffer]
  if handle then
    handle.detach()
    scene.handles[buffer] = nil
  end
  if vim.api.nvim_buf_is_valid(buffer) then
    vim.api.nvim_buf_clear_namespace(buffer, M.thread_namespace, 0, -1)
    if scene.mapped[buffer] then
      unmap_actions(buffer, FILE_ACTIONS)
      for _, extra in ipairs(scene.file_actions) do
        keymap.unmap(buffer, "n", extra[1])
      end
    end
  end
  scene.mapped[buffer] = nil
end

local function map_file_keys(state, buffer)
  local scene = state.scene
  if scene.mapped[buffer] then
    return
  end
  scene.mapped[buffer] = true
  keymap.map(buffer, "n", "next_file", function()
    M.show_file(state, state.file_cursor % #state.files + 1)
  end, "Next changed file")
  keymap.map(buffer, "n", "previous_file", function()
    M.show_file(state, (state.file_cursor - 2) % #state.files + 1)
  end, "Previous changed file")
  keymap.map(buffer, "n", "next_thread", function()
    M.show_thread(state, 1)
  end, "Next review thread")
  keymap.map(buffer, "n", "previous_thread", function()
    M.show_thread(state, -1)
  end, "Previous review thread")
  for _, extra in ipairs(scene.file_actions) do
    keymap.map(buffer, "n", extra[1], extra[2], extra[3])
  end
end

local function show_status(state)
  local scene = state.scene
  local shown = current_buffer(state)
  if shown ~= scene.status_buffer then
    release_buffer(state, shown)
  end
  ui.render(scene.status_buffer, M.status_view(state))
  if shown ~= scene.status_buffer then
    vim.api.nvim_win_set_buf(scene.window, scene.status_buffer)
  end
  ui.winbar(scene.window, M.winbar(state))
end

-- Shows a loading message (e.g. "Checking out feature…").
function M.set_loading(state, message, label)
  state.status = "loading"
  state.message = message
  if label then
    state.label = label
  end
  if alive(state) then
    show_status(state)
  end
end

-- Shows git's error as reported, and notifies it.
function M.fail(state, message)
  state.status = "error"
  state.error = message
  if alive(state) then
    show_status(state)
  end
  vim.notify(message, vim.log.levels.ERROR, { title = "proud" })
end

-- Attaches the pane to `window`. options:
--   buffer        status buffer to use (e.g. the host pane's buffer)
--   name          status buffer name when no buffer is given
--   file_actions  { { action, callback, description } } mapped on every
--                 shown file and the status buffer (e.g. toggle_sidebar)
--   on_file(index, file)  after a file is shown
-- Returns the status buffer.
function M.attach(state, window, options)
  options = options or {}
  local status_buffer = options.buffer or ui.buffer(options.name or "proud://diff/status")
  vim.api.nvim_win_set_buf(window, status_buffer)
  vim.wo[window].number = true
  vim.wo[window].signcolumn = "yes:2"
  vim.wo[window].cursorline = true
  state.scene = {
    window = window,
    status_buffer = status_buffer,
    handles = {},
    mapped = {},
    opened = {},
    scratch = {},
    file_actions = options.file_actions or {},
    on_file = options.on_file,
  }
  for _, extra in ipairs(state.scene.file_actions) do
    keymap.map(status_buffer, "n", extra[1], extra[2], extra[3])
  end
  show_status(state)
  return status_buffer
end

-- Removes every decoration and mapping from the buffers the pane used.
-- Call when the host scene closes.
function M.detach(state)
  local scene = state.scene
  if not scene or scene.detached then
    return
  end
  for buffer in pairs(vim.tbl_extend("force", {}, scene.handles, scene.mapped)) do
    release_buffer(state, buffer)
  end
  scene.detached = true
end

-- After the host's windows are gone: deletes commit snapshots and the
-- files the pane opened, unless they have unsaved edits or are shown
-- elsewhere. Files you had open before, or edited here, stay.
function M.unload(state)
  local scene = state.scene
  if not scene then
    return
  end
  for buffer in pairs(scene.scratch) do
    pcall(vim.api.nvim_buf_delete, buffer, { force = true })
  end
  for buffer in pairs(scene.opened) do
    if vim.api.nvim_buf_is_valid(buffer)
      and not vim.bo[buffer].modified
      and #vim.fn.win_findbuf(buffer) == 0
    then
      pcall(vim.api.nvim_buf_delete, buffer, {})
    end
  end
  pcall(vim.api.nvim_buf_delete, scene.status_buffer, { force = true })
  scene.scratch, scene.opened = {}, {}
end

local function lines_of(text)
  if text == "" then
    return {}
  end
  return vim.split((text:gsub("\n$", "")), "\n", { plain = true })
end

-- A read-only snapshot buffer (a commit's version, or a deleted file).
local function snapshot_buffer(state, name, path, text)
  local buffer = ui.buffer(name, { bo = { modifiable = true } })
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines_of(text))
  vim.bo[buffer].modifiable = false
  vim.bo[buffer].modified = false
  local filetype = vim.filetype.match({ filename = path, buf = buffer })
  if filetype and vim.bo[buffer].filetype ~= filetype then
    vim.bo[buffer].filetype = filetype
  end
  state.scene.scratch[buffer] = true
  return buffer
end

-- Marks every row of a deleted file's snapshot as deleted.
local function mark_deleted(buffer)
  vim.api.nvim_buf_clear_namespace(buffer, ui.inline_diff.namespace, 0, -1)
  for row = 0, vim.api.nvim_buf_line_count(buffer) - 1 do
    vim.api.nvim_buf_set_extmark(buffer, ui.inline_diff.namespace, row, 0, {
      line_hl_group = "ProudDeleteLine",
      sign_text = "-",
      sign_hl_group = "ProudDanger",
    })
  end
end

-- Base text, then the buffer that shows the file's new side.
local function resolve_file(state, file, callback)
  local source = state.source
  local base_rev = source.kind == "commit" and source.parent or source.base
  git.show(state.cwd, base_rev, file.old_path or file.path, function(ok, base)
    if not ok then
      return callback(false, base)
    end
    if not alive(state) then
      return
    end
    if file.status == "D" then
      local name = ("proud://deleted/%s/%s"):format(source.kind == "commit" and source.short or "worktree", file.path)
      return callback(true, base, snapshot_buffer(state, name, file.path, base), true)
    end
    if source.kind == "commit" then
      return git.show(state.cwd, source.sha, file.path, function(head_ok, head)
        if not head_ok then
          return callback(false, head)
        end
        if not alive(state) then
          return
        end
        local name = ("proud://commit/%s/%s"):format(source.short or source.sha:sub(1, 7), file.path)
        callback(true, base, snapshot_buffer(state, name, file.path, head), false)
      end)
    end
    local path = state.cwd .. "/" .. file.path
    local already_loaded = vim.fn.bufnr(path) ~= -1
    local edited, err = pcall(vim.api.nvim_win_call, state.scene.window, function()
      vim.cmd("hide edit " .. vim.fn.fnameescape(path))
    end)
    if not edited then
      return callback(false, ("Could not open %s\n%s"):format(file.path, tostring(err)))
    end
    local buffer = current_buffer(state)
    if not already_loaded then
      state.scene.opened[buffer] = true
    end
    callback(true, base, buffer, false)
  end)
end

-- Shows changed file `index` and attaches the live diff against its base.
-- on_ready(buffer) runs once decorated.
function M.show_file(state, index, on_ready)
  local scene = state.scene
  local file = state.files[index]
  if not file or not alive(state) then
    return
  end
  local previous = current_buffer(state)
  local source = state.source
  state.file_cursor = index
  resolve_file(state, file, function(ok, base, buffer, deleted)
    if not alive(state) or state.source ~= source then
      return
    end
    if not ok then
      return M.fail(state, base)
    end
    if current_buffer(state) ~= buffer then
      vim.api.nvim_win_set_buf(scene.window, buffer)
    end
    if previous ~= buffer and previous ~= scene.status_buffer then
      release_buffer(state, previous)
    end
    if scene.handles[buffer] then
      scene.handles[buffer].set_base(deleted and "" or base)
    else
      scene.handles[buffer] = ui.inline_diff.attach(buffer, {
        base = deleted and "" or base,
        on_update = function(stats)
          if alive(state) and current_buffer(state) == buffer then
            ui.winbar(scene.window, M.winbar(state, stats))
          end
        end,
      })
    end
    if deleted then
      mark_deleted(buffer)
      scene.handles[buffer].stats = { added = 0, deleted = vim.api.nvim_buf_line_count(buffer), hunks = 1 }
    end
    M.place_threads(state, buffer, file)
    map_file_keys(state, buffer)
    ui.winbar(scene.window, M.winbar(state, scene.handles[buffer].stats))
    if scene.on_file then
      scene.on_file(index, file)
    end
    if on_ready then
      on_ready(buffer)
    end
  end)
end

-- Replaces the file list. source: { kind = "worktree", base = rev } or
-- { kind = "commit", sha, short, parent }. options: label (window bar
-- segments), path (file to show first), on_ready.
function M.set_files(state, files, source, options)
  options = options or {}
  state.files = files or {}
  state.source = source
  state.label = options.label or state.label
  state.file_cursor = 1
  if not alive(state) then
    return
  end
  if #state.files == 0 then
    state.status = "empty"
    show_status(state)
    if options.on_ready then
      options.on_ready()
    end
    return
  end
  state.status = "ready"
  local index = 1
  for candidate, file in ipairs(state.files) do
    if file.path == options.path then
      index = candidate
    end
  end
  M.show_file(state, index, options.on_ready)
end

-- Selects the next/previous thread, opening its file, and moves the cursor
-- to the thread's (possibly moved) position.
function M.show_thread(state, delta)
  M.next_thread(state, delta)
  local thread = state.threads[state.thread_cursor]
  if not thread or not alive(state) or state.status ~= "ready" then
    return
  end
  local function jump(buffer)
    local mark = state.thread_marks and state.thread_marks[thread]
    if mark then
      local position = vim.api.nvim_buf_get_extmark_by_id(buffer, M.thread_namespace, mark, {})
      if position[1] then
        pcall(vim.api.nvim_win_set_cursor, state.scene.window, { position[1] + 1, 0 })
      end
    end
  end
  for index, file in ipairs(state.files) do
    if file.path == thread.path then
      if index == state.file_cursor then
        return jump(current_buffer(state))
      end
      return M.show_file(state, index, jump)
    end
  end
end

-- Replaces the review threads; re-places marks on the shown file.
function M.set_threads(state, threads)
  state.threads = vim.deepcopy(threads or {})
  state.thread_cursor = math.min(math.max(1, state.thread_cursor), math.max(1, #state.threads))
  if state.status == "ready" and alive(state) then
    local buffer = current_buffer(state)
    local file = state.files[state.file_cursor]
    if file and state.scene.handles[buffer] then
      M.place_threads(state, buffer, file)
    end
  end
end

-- The buffer currently shown, and its diff handle (nil while a status is
-- shown).
function M.current(state)
  if not alive(state) then
    return nil
  end
  local buffer = current_buffer(state)
  return buffer, state.scene.handles[buffer]
end

return M
