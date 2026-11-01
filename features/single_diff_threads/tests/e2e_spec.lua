return function(test)
  local feature = require("proud.loader").load("single_diff_threads")
  local fixtures = require("proud.fixtures")
  local state = feature.create(fixtures.overview, fixtures.threads, fixtures.patch, fixtures.file_sources)
  local buffer = feature.open(state)
  local code = state.workspace.panes.code
  test.eq(1, #state.workspace.order, "the single-pane diff has one pane")
  test.contains(vim.wo[code.window].winbar, "feat/task-retry-backoff", "the window bar shows the head branch")
  test.contains(vim.wo[code.window].winbar, "packages/runner/src/task/retry.ts", "the window bar shows the file")
  test.contains(vim.b[code.buffer].proud_title, "diff · single-pane", "the scene title names the single-pane mode")
  test.truthy(vim.wo[code.window].cursorline, "the cursor row is highlighted")
  local cursor_marks = vim.api.nvim_buf_get_extmarks(code.buffer, vim.api.nvim_create_namespace("proud_diff_cursor"), 0, -1, { details = true })
  test.eq(1, #cursor_marks, "the cursor row's line numbers are emphasized")
  vim.o.columns = math.max(80, vim.o.columns - 20)
  vim.api.nvim_exec_autocmds("VimResized", {})
  test.contains(vim.wo[code.window].winbar, "retry.ts", "the window bar survives a resize")
  vim.o.columns = vim.o.columns + 20
  vim.api.nvim_exec_autocmds("VimResized", {})
  vim.api.nvim_feedkeys("]f", "x", false)
  test.eq(2, state.file_cursor, "]f advances to the next file")
  test.contains(vim.wo[code.window].winbar, "2 / ", "the window bar follows the file")
  vim.api.nvim_feedkeys("[f", "x", false)
  test.eq(1, state.file_cursor, "[f returns to the previous file")
  vim.api.nvim_feedkeys("]t", "x", false)
  test.eq(2, state.thread_cursor, "]t selects the next thread")
  test.eq(2, state.file_cursor, "]t switches to the thread's file")
  test.contains(
    table.concat(vim.api.nvim_buf_get_lines(code.buffer, 0, -1, false), "\n"),
    "export type RunnerConfig"
  )
  local cursor_row = vim.api.nvim_win_get_cursor(code.window)[1]
  local cursor_line = vim.api.nvim_buf_get_lines(code.buffer, cursor_row - 1, cursor_row, false)[1]
  test.eq("   6", cursor_line:sub(6, 9), "]t puts the cursor on the thread's line")
  vim.api.nvim_feedkeys("R", "x", false)
  test.truthy(state.threads[2].resolved)
  local resolved_preview = false
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(code.buffer, -1, 0, -1, { details = true })) do
    local chunks = mark[4].virt_text
    if chunks and chunks[1][1]:find("◇ resolved", 1, true) then
      resolved_preview = true
    end
  end
  test.truthy(resolved_preview, "resolving updates the end-of-line preview")
  vim.cmd("silent! tabclose!")

  local session = require("proud.session")
  local credentials = require("proud.loader").load("github_credentials")
  local pull_callback
  local patch_callback
  local threads_callback
  local fake_client = {
    get_repository = function(_, callback)
      callback(true, { full_name = "acme/widget" })
    end,
    get_pull_request = function(_, _, callback)
      pull_callback = callback
    end,
    get_pull_request_diff = function(_, _, callback)
      patch_callback = callback
    end,
    list_review_comments = function(_, _, callback)
      threads_callback = callback
    end,
  }
  session.configure({
    kind = "github",
    repository = "acme/widget",
    token = "github_pat_diff_delayed",
    token_path = vim.fn.tempname(),
    credential = false,
    client = fake_client,
    cwd = vim.fn.getcwd(),
  })
  session.open_diff(904)
  test.truthy(vim.wait(2000, function()
    return session.current
      and session.current.feature == "single_diff_threads"
      and session.current.state.pull.number == 904
  end, 10), "diff scene opens before provider data")
  local delayed_state = session.current.state
  local code_buffer = delayed_state.workspace.panes.code.buffer
  test.contains(
    table.concat(vim.api.nvim_buf_get_lines(code_buffer, 0, -1, false), "\n"),
    "Loading diff...",
    "diff placeholder code pane is visible before PR and patch data"
  )
  test.truthy(pull_callback and threads_callback, "PR and review-thread requests start while the scene is open")
  threads_callback(true, fixtures.threads)
  pull_callback(true, vim.deepcopy(fixtures.overview))
  test.truthy(vim.wait(2000, function()
    return patch_callback ~= nil
  end, 10), "patch loading starts after pull metadata is available")
  patch_callback(true, fixtures.patch)
  test.truthy(not delayed_state.loading, "independent callbacks hydrate the open diff scene")
  test.contains(
    table.concat(vim.api.nvim_buf_get_lines(code_buffer, 0, -1, false), "\n"),
    "config.retry.maxAttempts",
    "patch data replaces the placeholder without reopening the scene"
  )
  vim.cmd("silent! tabclose!")
  credentials.reset()
end
