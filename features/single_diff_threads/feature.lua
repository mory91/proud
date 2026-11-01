-- Single-pane, editable diff on the checked-out pull request branch.
--
-- The PR branch is checked out in place (proud.git). Each changed file
-- opens as the real file, in a normal editable buffer with Neovim's own
-- line numbers, signs and syntax. ui.inline_diff compares it live with
-- the merge base: added/changed lines are highlighted, deleted lines are
-- shown as virtual lines, and edits update the diff as you type. Review
-- threads are signs plus end-of-line previews, placed as extmarks so they
-- move with the text. Git errors are shown to the user as git reports them.
local git = require("proud.git")
local ui = require("proud.ui")
local keymap = require("proud.keymap")

local M = {}

M.thread_namespace = vim.api.nvim_create_namespace("proud_diff_threads")
local PREVIEW_CHARS = 32
local FILE_ACTIONS = { "next_file", "previous_file", "next_thread", "previous_thread" }

function M.create(pull, threads, options)
  options = options or {}
  return {
    pull = require("proud.provider").normalize_pull_request(pull),
    threads = vim.deepcopy(threads or {}),
    files = {},
    file_cursor = 1,
    thread_cursor = 1,
    draft = "",
    status = "loading",
    cwd = options.cwd,
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

function M.title(state)
  return "#" .. tostring(state.pull.number) .. " diff · single-pane"
end

-- Window bar: base → head, path, live change counts, file position.
function M.winbar(state, stats)
  local pull = state.pull
  local segments = {
    { pull.base_ref or "main", "ProudAccentText" },
    { " → ", "ProudMuted" },
    { pull.head_ref or "feature", "ProudSuccessText" },
  }
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

-- Lines for the scene's status buffer while loading, on error, or when
-- there is nothing to show.
function M.status_view(state)
  local v = ui.view.new()
  local pull = state.pull
  if state.status == "error" then
    v:line({ "Could not open the diff for #" .. tostring(pull.number), "ProudDangerText" })
    v:blank()
    for _, line in ipairs(vim.split(state.error or "", "\n", { plain = true })) do
      v:line(line)
    end
  elseif state.status == "empty" then
    v:line({ "No changes", "ProudMuted" }, " between ", { pull.base_ref or "main", "ProudAccentText" }, " and ", { pull.head_ref or "", "ProudSuccessText" })
  else
    v:line({ "Checking out ", "ProudMuted" }, { pull.head_ref or ("#" .. tostring(pull.number)), "ProudSuccessText" }, { "…", "ProudMuted" })
  end
  return v:build()
end

local function scene_alive(state)
  local scene = state.scene
  return scene and not scene.lifecycle.closed() and vim.api.nvim_win_is_valid(scene.window)
end

local function show_status(state)
  local scene = state.scene
  ui.render(scene.status_buffer, M.status_view(state))
  if vim.api.nvim_win_get_buf(scene.window) ~= scene.status_buffer then
    vim.api.nvim_win_set_buf(scene.window, scene.status_buffer)
  end
  ui.winbar(scene.window, M.winbar(state))
end

local function fail(state, message)
  state.status = "error"
  state.error = message
  if scene_alive(state) then
    show_status(state)
  end
  vim.notify(message, vim.log.levels.ERROR, { title = "proud" })
end

-- Signs and end-of-line previews for the current file's threads.
-- Records each thread's extmark so navigation follows edits.
function M.place_threads(state, buffer, file)
  vim.api.nvim_buf_clear_namespace(buffer, M.thread_namespace, 0, -1)
  state.thread_marks = {}
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

-- Detaches the diff and thread marks and file mappings from `buffer`.
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
      for _, action in ipairs(FILE_ACTIONS) do
        keymap.unmap(buffer, "n", action)
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
end

-- Opens changed file `index` in the scene window and attaches the live
-- diff against the merge base. on_ready(buffer) runs once decorated.
function M.show_file(state, index, on_ready)
  local scene = state.scene
  local file = state.files[index]
  if not file or not scene_alive(state) then
    return
  end
  local previous = vim.api.nvim_win_get_buf(scene.window)
  state.file_cursor = index
  git.show(state.cwd, state.merge_base, file.old_path or file.path, function(ok, base)
    if not scene_alive(state) then
      return
    end
    if not ok then
      return fail(state, base)
    end
    local buffer
    if file.status == "D" then
      buffer = ui.buffer(("proud://pr/%s/deleted/%s"):format(tostring(state.pull.number), file.path))
      ui.render(buffer, { lines = vim.split(base:gsub("\n$", ""), "\n", { plain = true }) })
      vim.api.nvim_win_set_buf(scene.window, buffer)
    else
      local path = state.cwd .. "/" .. file.path
      local already_loaded = vim.fn.bufnr(path) ~= -1
      local edited, err = pcall(vim.api.nvim_win_call, scene.window, function()
        vim.cmd("hide edit " .. vim.fn.fnameescape(path))
      end)
      if not edited then
        return fail(state, ("Could not open %s\n%s"):format(file.path, tostring(err)))
      end
      buffer = vim.api.nvim_win_get_buf(scene.window)
      if not already_loaded then
        scene.opened[buffer] = true
      end
    end
    if previous ~= buffer and previous ~= scene.status_buffer then
      release_buffer(state, previous)
    end
    if not scene.handles[buffer] then
      scene.handles[buffer] = ui.inline_diff.attach(buffer, {
        base = file.status == "D" and "" or base,
        on_update = function(stats)
          if scene_alive(state) and vim.api.nvim_win_get_buf(scene.window) == buffer then
            ui.winbar(scene.window, M.winbar(state, stats))
          end
        end,
      })
      if file.status == "D" then
        -- The whole file is deleted: show its old text as deleted rows.
        vim.api.nvim_buf_clear_namespace(buffer, ui.inline_diff.namespace, 0, -1)
        for row = 0, vim.api.nvim_buf_line_count(buffer) - 1 do
          vim.api.nvim_buf_set_extmark(buffer, ui.inline_diff.namespace, row, 0, {
            line_hl_group = "ProudDelete",
            sign_text = "-",
            sign_hl_group = "ProudDanger",
          })
        end
      end
    else
      scene.handles[buffer].refresh()
    end
    M.place_threads(state, buffer, file)
    map_file_keys(state, buffer)
    ui.winbar(scene.window, M.winbar(state, scene.handles[buffer].stats))
    if on_ready then
      on_ready(buffer)
    end
  end)
end

-- Selects the next/previous thread, opening its file, and moves the cursor
-- to the thread's (possibly moved) position.
function M.show_thread(state, delta)
  M.next_thread(state, delta)
  local thread = state.threads[state.thread_cursor]
  if not thread or not scene_alive(state) then
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
        return jump(vim.api.nvim_win_get_buf(state.scene.window))
      end
      return M.show_file(state, index, jump)
    end
  end
end

-- Checks out the PR branch, computes the merge base and changed files, and
-- shows the first file (or options.path). Any git error is shown verbatim.
function M.load(state, options)
  options = options or {}
  local pull = state.pull
  if not scene_alive(state) then
    return
  end
  state.status = "loading"
  show_status(state)
  git.checkout_pull(state.cwd, pull, function(ok, branch)
    if not ok then
      return fail(state, branch)
    end
    state.branch = branch
    git.merge_base(state.cwd, pull.base_ref or "main", function(base_ok, merge_base)
      if not base_ok then
        return fail(state, merge_base)
      end
      state.merge_base = merge_base
      git.changed_files(state.cwd, merge_base, function(files_ok, files)
        if not files_ok then
          return fail(state, files)
        end
        state.files = files
        if #files == 0 then
          state.status = "empty"
          return show_status(state)
        end
        state.status = "ready"
        local index = 1
        for candidate, file in ipairs(files) do
          if file.path == options.path then
            index = candidate
          end
        end
        M.show_file(state, index, options.on_ready)
      end)
    end)
  end)
end

-- Applies new pull metadata or threads; re-places thread marks in place.
function M.hydrate(state, data)
  data = data or {}
  if data.pull ~= nil then
    state.pull = require("proud.provider").normalize_pull_request(data.pull)
  end
  if data.threads ~= nil then
    state.threads = vim.deepcopy(data.threads or {})
    state.thread_cursor = math.min(math.max(1, state.thread_cursor), math.max(1, #state.threads))
  end
  if state.status == "ready" and scene_alive(state) then
    local buffer = vim.api.nvim_win_get_buf(state.scene.window)
    local file = state.files[state.file_cursor]
    if file and state.scene.handles[buffer] then
      M.place_threads(state, buffer, file)
    end
  end
  return state
end

-- Opens the scene: a tab whose window shows real files. Until the checkout
-- finishes it shows a status buffer. options: cwd (repository), path
-- (file to open first), load (false to wait for M.load), on_ready.
function M.open(state, options)
  options = options or {}
  state.cwd = state.cwd or options.cwd or vim.fn.getcwd()
  vim.cmd("tabnew")
  local tabpage = vim.api.nvim_get_current_tabpage()
  local window = vim.api.nvim_get_current_win()
  local initial = vim.api.nvim_get_current_buf()
  local status_buffer = ui.buffer(("proud://pr/%s/diff/status"):format(tostring(state.pull.number)))
  vim.api.nvim_win_set_buf(window, status_buffer)
  vim.t[tabpage].proud_title = M.title(state)
  vim.wo[window].number = true
  vim.wo[window].signcolumn = "yes:2"
  vim.wo[window].cursorline = true
  vim.wo[window].winhighlight = "WinBar:ProudPanel,WinBarNC:ProudPanel"
  local scene = {
    tabpage = tabpage,
    window = window,
    status_buffer = status_buffer,
    handles = {},
    mapped = {},
    opened = {},
  }
  state.scene = scene
  scene.lifecycle = ui.create_scene_lifecycle({
    tabpage = tabpage,
    on_close = function()
      for buffer in pairs(vim.tbl_extend("force", {}, scene.handles, scene.mapped)) do
        release_buffer(state, buffer)
      end
    end,
    -- After the tab is gone: unload files this scene opened, unless they
    -- have unsaved edits or are shown elsewhere. Files you had open before
    -- the scene, or edited in it, stay.
    on_closed = function()
      for buffer in pairs(scene.opened) do
        if vim.api.nvim_buf_is_valid(buffer)
          and not vim.bo[buffer].modified
          and #vim.fn.win_findbuf(buffer) == 0
        then
          pcall(vim.api.nvim_buf_delete, buffer, {})
        end
      end
      scene.opened = {}
    end,
  })
  scene.lifecycle.track_window(window)
  scene.lifecycle.track_buffer(status_buffer)
  scene.lifecycle.track_buffer(initial)
  keymap.bind_common_buffer(status_buffer, {
    on_quit = function()
      scene.lifecycle.close()
    end,
  })
  state.close = scene.lifecycle.close
  show_status(state)
  if options.load ~= false then
    M.load(state, options)
  end
  return status_buffer
end

return M
