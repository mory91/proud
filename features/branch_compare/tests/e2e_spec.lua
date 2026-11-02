return function(test)
  local feature = require("proud.loader").load("branch_compare")
  local diff_view = require("proud.loader").load("diff_view")
  local fixtures = require("proud.fixtures")
  local fixture_repo = require("proud.fixture_repo")
  local git = require("proud.git")
  local session = require("proud.session")
  local credentials = require("proud.loader").load("github_credentials")
  local ui = require("proud.ui")

  local function plain(bar)
    return (bar or ""):gsub("%%#[%w_]+#", "")
  end
  local function lines(buffer)
    return table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
  end
  local function ready(state)
    local d = state.diff
    return d.status == "error" or d.status == "empty"
      or (d.status == "ready" and d.scene.handles[vim.api.nvim_win_get_buf(d.scene.window)] ~= nil)
  end
  local function branch(repo)
    return vim.trim(vim.system({ "git", "-C", repo.work, "branch", "--show-current" }, { text = true }):wait().stdout)
  end
  local function keys(value)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(value, true, false, true), "x", false)
  end
  local function select_node(state, id)
    local sidebar = require("proud.loader").load("sidebar")
    test.truthy(sidebar.components.tree.select(state.sidebar, id), "the sidebar has " .. id)
    local window = ui.workspace_window(state.workspace, "sidebar")
    sidebar.sync_cursor(state.sidebar, window)
    vim.api.nvim_set_current_win(window)
  end

  -- Wide enough for the sidebar's rows to fit.
  local columns = vim.o.columns
  vim.o.columns = 180

  -- A plain compare: the page opens at once, checks out the head in place
  -- and shows its changes in real files.
  local repo = fixture_repo.create()
  session.configure({ cwd = repo.work })
  session.open_compare("main", repo.head_ref)
  test.eq("branch_compare", session.current.feature, "the compare page opens before git resolves")
  local state = session.current.state
  local sidebar_buffer = ui.workspace_buffer(state.workspace, "sidebar")
  local diff_window = ui.workspace_window(state.workspace, "diff")
  test.eq({ "sidebar", "diff" }, state.workspace.order, "the page is a sidebar and a diff pane")
  test.contains(lines(sidebar_buffer), "Loading commits", "the sidebar shows placeholders while git works")
  vim.api.nvim_set_current_win(ui.workspace_window(state.workspace, "sidebar"))
  keys("S")
  test.eq("main", state.base, "swapping is ignored while a checkout is running")
  test.truthy(vim.wait(15000, function() return ready(state) end, 20), "the comparison loads")
  test.eq("ready", state.diff.status, "checkout and comparison succeed")
  test.eq(repo.head_ref, branch(repo), "the head branch is checked out in place")
  local sidebar_text = lines(sidebar_buffer)
  test.contains(sidebar_text, "Compare three-dot, from merge base", "the info section names the mode")
  test.contains(sidebar_text, "↑2 ahead  ↓0 behind  no PR yet", "ahead and behind are counted")
  test.contains(sidebar_text, "● All changes", "All changes is shown first")
  test.contains(sidebar_text, "Add exponential backoff", "the branch's commits are listed")
  test.contains(sidebar_text, "Files 2  +11 −2", "the changed files are counted")
  local first = vim.api.nvim_win_get_buf(diff_window)
  test.eq("", vim.bo[first].buftype, "All changes shows the real file")
  test.truthy(vim.bo[first].modifiable, "the real file is editable")
  test.contains(plain(vim.wo[diff_window].winbar), "main...feat/task-retry-backoff   packages/runner/src/config.ts   [+5 −0]   1 / 2", "the window bar shows the range and file")

  -- ]f in the diff moves the sidebar's file selection along.
  vim.api.nvim_set_current_win(diff_window)
  keys("]f")
  test.truthy(vim.wait(5000, function() return state.diff.file_cursor == 2 and ready(state) and vim.api.nvim_win_get_buf(diff_window) ~= first end, 20), "]f opens the next file")
  test.eq("file:packages/runner/src/task/retry.ts", state.sidebar.selected_id, "the sidebar follows the shown file")

  -- A file in the sidebar opens in the diff pane and takes focus.
  select_node(state, "file:packages/runner/src/config.ts")
  keys("<CR>")
  test.truthy(vim.wait(5000, function() return state.diff.file_cursor == 1 and ready(state) end, 20), "<CR> on a file opens it")
  test.eq(diff_window, vim.api.nvim_get_current_win(), "the diff pane takes focus to edit")

  -- A commit shows that commit against its parent.
  local commit = state.commits[1]
  select_node(state, "commit:" .. commit.sha)
  keys("<CR>")
  test.truthy(vim.wait(5000, function() return state.commit == commit.sha and ready(state) and vim.bo[vim.api.nvim_win_get_buf(diff_window)].buftype ~= "" end, 20), "<CR> on a commit shows its change")
  test.contains(lines(sidebar_buffer), "● " .. commit.short, "the commit is marked selected")
  test.contains(lines(sidebar_buffer), "Files 1", "the files are the commit's")
  test.truthy(not vim.bo[vim.api.nvim_win_get_buf(diff_window)].modifiable, "a commit's version is read-only")
  test.contains(plain(vim.wo[diff_window].winbar), commit.short .. "  " .. commit.message, "the window bar names the commit")
  select_node(state, "commit:all")
  keys("<CR>")
  test.truthy(vim.wait(5000, function() return state.commit == nil and ready(state) and vim.bo[vim.api.nvim_win_get_buf(diff_window)].buftype == "" end, 20), "All changes shows the real files again")

  -- The sidebar hides and comes back without closing the page.
  vim.api.nvim_set_current_win(diff_window)
  keys("<leader>e")
  test.truthy(not ui.pane_visible(state.workspace, "sidebar"), "<leader>e hides the sidebar")
  test.eq(1, #vim.api.nvim_tabpage_list_wins(state.workspace.tabpage), "only the diff pane remains")
  test.truthy(not state.workspace.lifecycle.closed(), "hiding the sidebar keeps the page open")
  keys("<leader>e")
  test.truthy(ui.pane_visible(state.workspace, "sidebar"), "<leader>e shows the sidebar again")
  test.eq(diff_window, vim.api.nvim_get_current_win(), "showing the sidebar keeps focus")
  test.contains(lines(sidebar_buffer), "● All changes", "the sidebar keeps its content")

  -- Swapping checks out the other branch.
  vim.api.nvim_set_current_win(ui.workspace_window(state.workspace, "sidebar"))
  keys("S")
  test.truthy(vim.wait(15000, function() return state.head == "main" and not state.loading and ready(state) end, 20), "S swaps base and head")
  test.eq("main", branch(repo), "the new head is checked out")
  test.eq("empty", state.diff.status, "main has nothing that is not in the branch")

  vim.api.nvim_set_current_win(ui.workspace_window(state.workspace, "sidebar"))
  keys("q")
  test.truthy(vim.wait(1000, function() return state.workspace.lifecycle.closed() end, 10), "q closes the page")
  fixture_repo.remove(repo)

  -- Git errors are shown as git reports them.
  local dirty = fixture_repo.create()
  vim.fn.writefile({ "local uncommitted change" }, dirty.work .. "/packages/runner/src/config.ts")
  local failing = feature.create({ pull = fixtures.overview, threads = fixtures.threads, cwd = dirty.work })
  local notified
  local notify = vim.notify
  vim.notify = function(message) notified = message end
  feature.open(failing)
  test.truthy(vim.wait(15000, function() return failing.diff.status == "error" end, 20), "a conflicting local change stops the checkout")
  vim.notify = notify
  local status_text = lines(failing.diff.scene.status_buffer)
  test.contains(status_text, "Could not open the diff for #482", "the diff pane reports the failure")
  test.contains(status_text, "would be overwritten by checkout", "git's own message is shown")
  test.contains(notified or "", "would be overwritten by checkout", "the error is also notified")
  test.truthy(not failing.loading, "the sidebar stops loading")
  failing.close()
  fixture_repo.remove(dirty)

  -- A pull request's diff opens before provider data, then hydrates.
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
  test.truthy(vim.wait(2000, function() return session.current and session.current.feature == "branch_compare" end, 10), "the diff page opens before provider data")
  local delayed = session.current.state
  test.contains(lines(delayed.diff.scene.status_buffer), "Loading #482", "the page waits for pull metadata")
  test.truthy(pull_callback and threads_callback, "PR and thread requests start while the page is open")
  pull_callback(true, vim.deepcopy(fixtures.overview))
  test.truthy(vim.wait(15000, function() return ready(delayed) end, 20), "pull metadata starts the checkout")
  test.eq("ready", delayed.diff.status, "the PR loads")
  test.eq(2, delayed.diff.file_cursor, "the requested file opens first")
  test.contains(lines(ui.workspace_buffer(delayed.workspace, "sidebar")), "#482", "the sidebar names the PR")
  threads_callback(true, {})
  test.eq(0, #delayed.diff.threads, "threads hydrate independently")
  delayed.close()
  vim.wait(1000, function() return delayed.workspace.lifecycle.closed() end, 10)
  fixture_repo.remove(live)
  credentials.reset()

  -- The overview starts the checkout; the diff joins it with the
  -- overview's metadata, and can open on one commit.
  local background = fixture_repo.create()
  local pull_requests = 0
  session.configure({
    kind = "github",
    repository = "acme/widget",
    token = "github_pat_diff_background",
    token_path = vim.fn.tempname(),
    credential = false,
    cwd = background.work,
    client = {
      get_repository = function(_, callback) callback(true, { full_name = "acme/widget" }) end,
      get_pull_request = function(_, _, callback)
        pull_requests = pull_requests + 1
        if pull_requests == 1 then
          callback(true, vim.deepcopy(fixtures.overview))
        end
      end,
      list_review_comments = function(_, _, callback) callback(true, {}) end,
    },
  })
  session.open_overview(482)
  test.truthy(vim.wait(15000, function() return git.preparation(background.work, fixtures.overview) == "ready" end, 20), "opening the overview prepares the PR in the background")
  test.eq("feat/task-retry-backoff", branch(background), "the PR branch is checked out before the diff opens")
  local overview_tab = vim.api.nvim_get_current_tabpage()
  local head_commit = vim.trim(vim.system({ "git", "-C", background.work, "rev-parse", "HEAD" }, { text = true }):wait().stdout)
  session.open_diff(482, nil, head_commit)
  local joined = session.current.state
  test.eq("feat/task-retry-backoff", joined.head, "the diff starts with the overview's metadata")
  test.truthy(vim.wait(5000, function() return ready(joined) end, 20), "the diff opens from the prepared checkout")
  test.eq(nil, git.preparation(background.work, fixtures.overview), "the diff claims the prepared checkout")
  test.eq(head_commit, joined.commit, "the requested commit is selected")
  test.eq(1, #joined.diff.files, "the commit's files are shown")
  joined.close()
  vim.wait(1000, function() return joined.workspace.lifecycle.closed() end, 10)
  if vim.api.nvim_tabpage_is_valid(overview_tab) and #vim.api.nvim_list_tabpages() > 1 then
    vim.api.nvim_set_current_tabpage(overview_tab)
    vim.cmd("tabclose")
  end
  fixture_repo.remove(background)
  credentials.reset()
  test.eq(nil, diff_view.alive(joined.diff) and true or nil, "the closed page's diff pane is detached")
  vim.o.columns = columns
end
