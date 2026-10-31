return function(test)
  local feature = require("proud.loader").load("single_diff_threads")
  local fixtures = require("proud.fixtures")
  local state = feature.create(fixtures.overview, fixtures.threads, fixtures.patch, fixtures.file_sources)
  local buffer = feature.open(state)
  vim.api.nvim_feedkeys("]f", "x", false)
  test.eq(2, state.file_cursor, "]f advances to the next file")
  vim.api.nvim_feedkeys("[f", "x", false)
  test.eq(1, state.file_cursor, "[f returns to the previous file")
  vim.api.nvim_win_set_cursor(state.workspace.panes.files.window, { 3, 0 })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
  test.eq(2, state.file_cursor, "<CR> selects the focused file row")
  test.contains(
    table.concat(vim.api.nvim_buf_get_lines(state.workspace.panes.code.buffer, 0, -1, false), "\n"),
    "export type RunnerConfig"
  )
  vim.api.nvim_feedkeys("]t", "x", false)
  vim.api.nvim_feedkeys("R", "x", false)
  test.eq(2, state.thread_cursor)
  test.truthy(state.threads[2].resolved)
  test.contains(
    table.concat(vim.api.nvim_buf_get_lines(state.workspace.panes.thread.buffer, 0, -1, false), "\n"),
    "◇"
  )
  test.eq(3, #state.workspace.order, "single diff uses files, code, and thread panes")
  test.truthy(state.workspace.panes.files.buffer ~= state.workspace.panes.code.buffer)
  test.truthy(state.workspace.panes.code.buffer ~= state.workspace.panes.thread.buffer)
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
