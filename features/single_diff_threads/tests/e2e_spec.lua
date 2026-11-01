return function(test)
  local feature = require("proud.loader").load("single_diff_threads")
  local fixtures = require("proud.fixtures")
  local fixture_repo = require("proud.fixture_repo")
  local inline = require("proud.ui.inline_diff")

  local function plain(bar)
    return (bar or ""):gsub("%%#[%w_]+#", "")
  end
  local function current_buffer(state)
    return vim.api.nvim_win_get_buf(state.scene.window)
  end
  local function ready(state)
    return state.status == "error"
      or (state.status == "ready" and state.scene.handles[current_buffer(state)] ~= nil)
  end

  -- Checkout in place, real editable file, live diff, threads, navigation.
  local repo = fixture_repo.create()
  local state = feature.create(fixtures.overview, fixtures.threads, { cwd = repo.work })
  feature.open(state)
  test.truthy(vim.wait(15000, function() return ready(state) end, 20), "the diff loads after checkout")
  test.eq("ready", state.status, "checkout and merge base succeed")
  local branch = vim.trim(vim.system({ "git", "-C", repo.work, "branch", "--show-current" }, { text = true }):wait().stdout)
  test.eq("feat/task-retry-backoff", branch, "the PR branch is checked out in place")
  local window = state.scene.window
  local buffer = current_buffer(state)
  test.eq(
    vim.uv.fs_realpath(repo.work .. "/packages/runner/src/config.ts"),
    vim.uv.fs_realpath(vim.api.nvim_buf_get_name(buffer)),
    "the real file is opened"
  )
  test.eq("", vim.bo[buffer].buftype, "the file is a normal buffer")
  test.truthy(vim.bo[buffer].modifiable, "the file is editable")
  test.truthy(vim.wo[window].number, "Neovim's own line numbers are used")
  test.eq("#482 diff · single-pane", vim.t[state.scene.tabpage].proud_title, "the tab is titled")
  test.contains(plain(vim.wo[window].winbar), "packages/runner/src/config.ts   [+5 −0]   1 / 2", "the window bar shows file, counts and position")
  local added = 0
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, inline.namespace, 0, -1, { details = true })) do
    if mark[4].line_hl_group == "ProudAdd" then
      added = added + 1
    end
  end
  test.eq(5, added, "added lines are highlighted")
  local thread_marks = vim.api.nvim_buf_get_extmarks(buffer, feature.thread_namespace, 0, -1, { details = true })
  test.eq(1, #thread_marks, "the file's thread is marked")
  test.eq(5, thread_marks[1][2], "the thread sits on its line")
  test.eq("◆", vim.trim(thread_marks[1][4].sign_text), "open threads get a sign")
  test.contains(thread_marks[1][4].virt_text[1][1], "◆ dev-lee: Can maxDelayMs", "open threads preview their first comment")

  vim.api.nvim_buf_set_lines(buffer, 0, 0, false, { "// local edit" })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buffer })
  test.truthy(vim.wait(2000, function() return plain(vim.wo[window].winbar):find("[+6 −0]", 1, true) ~= nil end, 10), "editing updates the diff live")
  local moved = vim.api.nvim_buf_get_extmark_by_id(buffer, feature.thread_namespace, thread_marks[1][1], {})
  test.eq(6, moved[1], "thread marks move with edits")

  vim.api.nvim_set_current_win(window)
  vim.api.nvim_feedkeys("]f", "x", false)
  test.truthy(vim.wait(5000, function() return state.file_cursor == 2 and ready(state) and current_buffer(state) ~= buffer end, 20), "]f opens the next file")
  test.contains(plain(vim.wo[window].winbar), "task/retry.ts   [+6 −2]   2 / 2", "the window bar follows the file")
  test.truthy(vim.bo[buffer].modified, "the previous file keeps its unsaved edit")
  test.eq(0, #vim.tbl_filter(function(map) return map.lhs == "]f" end, vim.api.nvim_buf_get_keymap(buffer, "n")), "the previous file's mappings are removed")
  local deleted = 0
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(current_buffer(state), inline.namespace, 0, -1, { details = true })) do
    deleted = deleted + #(mark[4].virt_lines or {})
  end
  test.eq(2, deleted, "deleted lines are shown as virtual lines")

  state.thread_cursor = 2
  vim.api.nvim_feedkeys("]t", "x", false)
  test.truthy(vim.wait(5000, function() return state.file_cursor == 2 and vim.api.nvim_win_get_cursor(window)[1] == 14 end, 20), "]t jumps to the thread's line")

  local retry_buffer = current_buffer(state)
  state.close()
  test.truthy(vim.wait(2000, function() return state.scene.lifecycle.closed() end, 10), "the scene closes")
  test.truthy(not vim.api.nvim_buf_is_valid(retry_buffer), "closing unloads unmodified files the scene opened")
  test.truthy(vim.api.nvim_buf_is_valid(buffer) and vim.bo[buffer].modified, "closing keeps files with unsaved edits")
  test.eq(0, #vim.api.nvim_buf_get_extmarks(buffer, inline.namespace, 0, -1, {}), "closing removes diff decorations from kept files")
  test.eq(0, #vim.api.nvim_buf_get_extmarks(buffer, feature.thread_namespace, 0, -1, {}), "closing removes thread marks from kept files")
  test.eq(0, #vim.tbl_filter(function(map) return map.lhs == "]t" or map.lhs == "]f" end, vim.api.nvim_buf_get_keymap(buffer, "n")), "closing removes mappings from kept files")
  pcall(vim.api.nvim_buf_delete, buffer, { force = true })
  fixture_repo.remove(repo)

  -- Git errors are shown as git reports them.
  local dirty = fixture_repo.create()
  vim.fn.writefile({ "local uncommitted change" }, dirty.work .. "/packages/runner/src/config.ts")
  local failing = feature.create(fixtures.overview, fixtures.threads, { cwd = dirty.work })
  local notified
  local notify = vim.notify
  vim.notify = function(message) notified = message end
  feature.open(failing)
  test.truthy(vim.wait(15000, function() return failing.status == "error" end, 20), "a conflicting local change stops the checkout")
  vim.notify = notify
  local status_text = table.concat(vim.api.nvim_buf_get_lines(failing.scene.status_buffer, 0, -1, false), "\n")
  test.contains(status_text, "Could not open the diff for #482", "the scene reports the failure")
  test.contains(status_text, "would be overwritten by checkout", "git's own message is shown")
  test.contains(notified or "", "would be overwritten by checkout", "the error is also notified")
  failing.close()
  fixture_repo.remove(dirty)

  -- The session opens the diff before provider data and hydrates threads.
  local session = require("proud.session")
  local credentials = require("proud.loader").load("github_credentials")
  local live = fixture_repo.create()
  local pull_callback
  local threads_callback
  session.configure({
    kind = "github",
    repository = "acme/widget",
    token = "github_pat_diff_delayed",
    token_path = vim.fn.tempname(),
    credential = false,
    cwd = live.work,
    client = {
      get_repository = function(_, callback) callback(true, { full_name = "acme/widget" }) end,
      get_pull_request = function(_, _, callback) pull_callback = callback end,
      list_review_comments = function(_, _, callback) threads_callback = callback end,
    },
  })
  session.open_diff(482, "packages/runner/src/task/retry.ts")
  test.truthy(vim.wait(2000, function()
    return session.current and session.current.feature == "single_diff_threads"
  end, 10), "the diff scene opens before provider data")
  local delayed = session.current.state
  test.eq("loading", delayed.status, "the scene waits for pull metadata")
  test.truthy(pull_callback and threads_callback, "PR and thread requests start while the scene is open")
  pull_callback(true, vim.deepcopy(fixtures.overview))
  test.truthy(vim.wait(15000, function() return ready(delayed) end, 20), "pull metadata starts the checkout")
  test.eq(2, delayed.file_cursor, "the requested file opens first")
  threads_callback(true, {})
  test.eq(0, #delayed.threads, "threads hydrate independently")
  local opened = current_buffer(delayed)
  delayed.close()
  vim.wait(1000, function() return delayed.scene.lifecycle.closed() end, 10)
  pcall(vim.api.nvim_buf_delete, opened, { force = true })
  fixture_repo.remove(live)
  credentials.reset()
end
