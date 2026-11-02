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
local FILE_ACTIONS = { "next_file", "previous_file", "next_thread", "previous_thread", "show_thread" }
local THREAD_WINDOW_WIDTH = 84

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

-- Threads whose marks sit on buffer row `row` (0-based) of the shown file.
function M.threads_at(state, buffer, row)
  local found = {}
  for _, thread in ipairs(state.threads) do
    local mark = state.thread_marks and state.thread_marks[thread]
    if mark then
      local position = vim.api.nvim_buf_get_extmark_by_id(buffer, M.thread_namespace, mark, {})
      if position[1] == row then
        found[#found + 1] = thread
      end
    end
  end
  return found
end

-- Full text of `threads` (those on one line) for the thread window, wrapped
-- to `width` cells: a header per thread, then every comment in full.
function M.thread_view(threads, width)
  width = math.max(20, math.floor(width or THREAD_WINDOW_WIDTH))
  local v = ui.view.new()
  for index, thread in ipairs(threads) do
    if index > 1 then
      v:blank()
    end
    local resolved = thread.resolved
    local comments = thread.comments or {}
    v:spans(
      " ", nil,
      resolved and "◇ " or "◆ ", resolved and "ProudSuccessText" or "ProudWarning",
      vim.fn.fnamemodify(thread.path or "", ":t") .. ":" .. tostring(thread.line or "?"), "ProudBright",
      "  · ", "ProudMuted",
      resolved and "resolved" or "unresolved", resolved and "ProudSuccessText" or "ProudDangerText",
      ("  · %d comment%s"):format(#comments, #comments == 1 and "" or "s"), "ProudMuted"
    )
    for position, comment in ipairs(comments) do
      -- Replies are indented under the comment that opened the thread.
      local indent = position == 1 and " " or "   "
      v:blank()
      v:spans(
        indent, nil,
        position == 1 and "" or "↳ ", "ProudMuted",
        tostring(comment.author or "unknown"), "ProudAccentText",
        "  · " .. tostring(comment.age or ""), "ProudMuted"
      )
      local body = tostring(comment.body or "")
      if body == "" then
        v:spans(indent, nil, "(no message)", "ProudMuted")
      end
      local body_indent = position == 1 and indent or indent .. "  "
      for paragraph in (body .. "\n"):gmatch("(.-)\r?\n") do
        if paragraph == "" then
          if body ~= "" then
            v:blank()
          end
        else
          for _, line in ipairs(ui.wrap_text(paragraph, width - #body_indent - 1, { wrap = true })) do
            v:spans(body_indent, nil, line, "ProudText")
          end
        end
      end
    end
  end
  return v:build()
end

-- Closes the thread window, if open.
function M.close_thread_window(state)
  local thread_window = state.thread_window
  state.thread_window = nil
  if not thread_window then
    return
  end
  pcall(vim.api.nvim_del_augroup_by_id, thread_window.group)
  if vim.api.nvim_win_is_valid(thread_window.window) then
    pcall(vim.api.nvim_win_close, thread_window.window, true)
  end
  if vim.api.nvim_buf_is_valid(thread_window.buffer) then
    pcall(vim.api.nvim_buf_delete, thread_window.buffer, { force = true })
  end
end

-- Opens a floating window with the full threads on the cursor's line,
-- next to that line. When it is already open for that line, focuses it
-- (like K for LSP hover). options.focus focuses it right away. Returns
-- false when the line has no thread.
function M.open_thread_window(state, options)
  options = options or {}
  if not alive(state) or state.status ~= "ready" then
    return false
  end
  local scene = state.scene
  local window = scene.window
  local shown = current_buffer(state)
  local row = vim.api.nvim_win_get_cursor(window)[1] - 1
  local open = state.thread_window
  if open and vim.api.nvim_win_is_valid(open.window) and open.row == row and open.shown == shown then
    vim.api.nvim_set_current_win(open.window)
    return true
  end
  local threads = M.threads_at(state, shown, row)
  M.close_thread_window(state)
  if #threads == 0 then
    return false
  end

  local info = vim.fn.getwininfo(window)[1] or { width = vim.api.nvim_win_get_width(window), textoff = 0 }
  local width = math.max(20, math.min(THREAD_WINDOW_WIDTH, info.width - info.textoff - 3))
  local view = M.thread_view(threads, width)
  -- Below the line when it fits, else above when there is more room.
  local window_height = vim.api.nvim_win_get_height(window)
  local line_row = vim.fn.winline() - 1
  if vim.api.nvim_get_current_win() ~= window then
    line_row = math.max(0, row - (vim.fn.line("w0", window) - 1))
  end
  local below = window_height - line_row - 3
  local above = line_row - 2
  local place_above = below < math.min(#view.lines, 8) and above > below
  local rows = 0
  for _, line in ipairs(view.lines) do
    rows = rows + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
  end
  local height = math.max(1, math.min(rows, math.floor(window_height * 0.6), place_above and above or below))

  local buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].filetype = "proud-thread"
  ui.render(buffer, view)
  vim.bo[buffer].modifiable = false
  local float = vim.api.nvim_open_win(buffer, false, {
    relative = "win",
    win = window,
    bufpos = { row, 0 },
    row = place_above and 0 or 1,
    col = 0,
    anchor = place_above and "SW" or "NW",
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = { { #threads > 1 and (" %d threads "):format(#threads) or " Thread ", "ProudMuted" } },
    title_pos = "left",
    footer = { { " K focus · q close ", "ProudMuted" } },
    footer_pos = "right",
    focusable = true,
    zindex = 60,
  })
  ui.winhighlight(float, { NormalFloat = "ProudCard", FloatBorder = "ProudCardBorder", FloatTitle = "ProudMuted", FloatFooter = "ProudMuted" })
  -- Comments are wrapped already; wrap lets a long header fit narrow windows.
  vim.wo[float].wrap = true
  vim.wo[float].linebreak = true
  vim.wo[float].cursorline = false

  local group = vim.api.nvim_create_augroup("ProudThreadWindow" .. float, { clear = true })
  state.thread_window = { window = float, buffer = buffer, row = row, shown = shown, group = group, threads = threads }
  local function close()
    if state.thread_window and state.thread_window.window == float then
      M.close_thread_window(state)
    end
  end
  -- Closes when the cursor leaves the line, on edits, or when the diff
  -- window shows another buffer or closes.
  vim.api.nvim_create_autocmd({ "CursorMoved" }, {
    group = group,
    buffer = shown,
    callback = function()
      if vim.api.nvim_get_current_win() == window and vim.api.nvim_win_get_cursor(window)[1] - 1 ~= row then
        close()
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "InsertEnter", "BufWinLeave" }, { group = group, buffer = shown, callback = close })
  vim.api.nvim_create_autocmd("WinClosed", { group = group, pattern = tostring(window), callback = close })
  -- Leaving the focused window closes it, like LSP hover.
  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    buffer = buffer,
    callback = function()
      vim.schedule(close)
    end,
  })
  -- K inside the window has nothing more to show (and must not run
  -- keywordprg on the comment text).
  keymap.map(buffer, "n", "show_thread", function() end, "Already showing the thread")
  keymap.map(buffer, "n", "close_thread", function()
    close()
    if vim.api.nvim_win_is_valid(window) then
      vim.api.nvim_set_current_win(window)
    end
  end, "Close the thread window")
  if options.focus then
    vim.api.nvim_set_current_win(float)
  end
  return true
end

-- K where the line has no thread: LSP hover, else Neovim's K.
local function hover_fallback(buffer)
  if #vim.lsp.get_clients({ bufnr = buffer }) > 0 then
    vim.lsp.buf.hover()
  else
    pcall(vim.cmd, "normal! K")
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
  if state.thread_window and state.thread_window.shown == buffer then
    M.close_thread_window(state)
  end
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
  keymap.map(buffer, "n", "show_thread", function()
    if not M.open_thread_window(state) then
      hover_fallback(buffer)
    end
  end, "Show the full review thread on this line")
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
  M.close_thread_window(state)
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
-- An open thread window follows to the new thread.
function M.show_thread(state, delta)
  M.next_thread(state, delta)
  local thread = state.threads[state.thread_cursor]
  if not thread or not alive(state) or state.status ~= "ready" then
    return
  end
  local following = state.thread_window ~= nil
  local function jump(buffer)
    local mark = state.thread_marks and state.thread_marks[thread]
    if mark then
      local position = vim.api.nvim_buf_get_extmark_by_id(buffer, M.thread_namespace, mark, {})
      if position[1] then
        pcall(vim.api.nvim_win_set_cursor, state.scene.window, { position[1] + 1, 0 })
        if following then
          M.close_thread_window(state)
          M.open_thread_window(state)
        end
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
  M.close_thread_window(state)
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
