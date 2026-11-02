return function(test)
  local feature = require("proud.loader").load("pull_request_overview")
  local fixtures = require("proud.fixtures")
  local state = feature.create(fixtures.overview)
  local opened_diff = false
  local opened_commit
  local buffer = feature.open(state, {
    current_path = "packages/runner/src/task/retry.ts",
    on_diff = function()
      opened_diff = true
    end,
    on_commit = function(sha)
      opened_commit = sha
    end,
  })
  vim.api.nvim_feedkeys("v", "x", false)
  test.eq(2, feature.viewed_count(state), "v marks selected file viewed")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
  test.truthy(opened_diff, "<CR> opens the full-file diff from overview")
  local tree = require("proud.components.tree")
  tree.select(state.sidebar, "commit:a3f91c2")
  require("proud.loader").load("sidebar").sync_cursor(state.sidebar, state.workspace.panes.sidebar.window)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
  test.eq("a3f91c2", opened_commit, "<CR> on a commit opens the diff on that commit")
  tree.select(state.sidebar, "file:packages/runner/src/task/retry.ts")
  local overview_tab = state.workspace.tabpage
  local function splits()
    return #vim.tbl_filter(function(window)
      return vim.api.nvim_win_get_config(window).relative == ""
    end, vim.api.nvim_tabpage_list_wins(overview_tab))
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<leader>e", true, false, true), "x", false)
  test.eq(1, splits(), "<leader>e hides the overview sidebar")
  test.eq(state.workspace.panes.details.window, vim.api.nvim_get_current_win(), "focus moves to the details pane")
  test.truthy(not state.workspace.lifecycle.closed(), "hiding the sidebar keeps the overview open")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<leader>e", true, false, true), "x", false)
  test.eq(2, splits(), "<leader>e shows it again")
  test.contains(table.concat(vim.api.nvim_buf_get_lines(state.workspace.panes.sidebar.buffer, 0, -1, false), "\n"), "Files 5", "the sidebar keeps its content")
  vim.api.nvim_set_current_win(state.workspace.panes.sidebar.window)
  test.truthy(vim.api.nvim_buf_is_valid(buffer))
  test.eq({ "sidebar", "details" }, state.workspace.order, "overview uses sidebar and details panes")
  test.truthy(state.workspace.panes.sidebar.buffer ~= state.workspace.panes.details.buffer)
  local collapse_map = vim.fn.maparg("c", "n", false, true)
  test.contains(collapse_map.desc or "", "Collapse", "sidebar-specific collapse survives workspace-wide comment mapping")
  local sidebar_text = table.concat(vim.api.nvim_buf_get_lines(state.workspace.panes.sidebar.buffer, 0, -1, false), "\n")
  test.contains(sidebar_text, "Files 5 · 2 of 5 viewed")
  test.contains(sidebar_text, "a3f91c2")
  local selected_node = require("proud.components.tree").find(state.sidebar, "file:packages/runner/src/task/retry.ts")
  test.contains(table.concat(vim.tbl_map(function(section)
    return section.text or ""
  end, selected_node.sections), "\n"), "viewed", "selected file row carries the viewed section")
  state.pull.title = "A long overview title that must wrap through the details pane without entering either configured content margin"
  state.body = {
    "This long description sentence contains enough ordinary words to wrap naturally while staying within both details-pane margins.",
    "## This long heading also wraps and must preserve its semantic Markdown styling inside the constrained content box",
  }
  local details = state.workspace.panes.details
  local details_width = vim.api.nvim_win_get_width(details.window)
  local original_wrap = vim.go.wrap
  vim.go.wrap = true
  vim.wo[details.window].wrap = true
  state.refresh()
  for _, line in ipairs(vim.api.nvim_buf_get_lines(details.buffer, 0, -1, false)) do
    test.eq(details_width, vim.fn.strdisplaywidth(line), "wrapped overview lines remain padded on both sides")
    test.eq("  ", line:sub(1, 2), "wrapped overview lines preserve left padding")
    test.eq("  ", line:sub(-2), "wrapped overview lines preserve right padding")
  end
  test.contains(table.concat(vim.api.nvim_buf_get_lines(details.buffer, 0, -1, false), "\n"), "long description sentence", "wrapped description text remains visible")
  vim.go.wrap = false
  vim.wo[details.window].wrap = false
  state.refresh()
  local text_frame = state.workspace.panes.details.text_frame
  local geometry = text_frame and text_frame:geometry()
  test.truthy(geometry ~= nil, "non-wrapped overview uses fixed text margins")
  test.eq(2, geometry.padding, "overview left text margin remains fixed while text overflows")
  test.eq(0, geometry.left_col, "overview left text margin stays at the pane edge")
  test.eq(details_width - 2, geometry.right_col, "overview right text margin stays at the pane edge")
  local nonwrapped_lines = vim.api.nvim_buf_get_lines(details.buffer, 0, -1, false)
  for _, line in ipairs(nonwrapped_lines) do
    test.eq("  ", line:sub(1, 2), "non-wrapped overview lines preserve left padding")
  end
  test.contains(table.concat(nonwrapped_lines, "\n"), "A long overview title that must wrap through", "non-wrapped overview retains complete text for horizontal navigation")
  local long_row, long_line = 1, ""
  for row, line in ipairs(nonwrapped_lines) do
    if vim.fn.strdisplaywidth(line) > vim.fn.strdisplaywidth(long_line) then
      long_row, long_line = row, line
    end
  end
  test.truthy(vim.fn.strdisplaywidth(long_line) > details_width, "non-wrapped overview keeps overflow available beyond the viewport")
  local leftcol = vim.api.nvim_win_call(details.window, function()
    vim.api.nvim_win_set_cursor(details.window, { long_row, math.max(0, #long_line - 1) })
    vim.cmd("normal! ze")
    return vim.fn.winsaveview().leftcol
  end)
  test.truthy(leftcol > 0, "native horizontal navigation reveals non-wrapped overview overflow")
  geometry = text_frame:geometry()
  test.eq(2, geometry.padding, "horizontal navigation keeps the left text margin fixed")
  test.eq(details_width - 2, geometry.right_col, "horizontal navigation keeps the right text margin fixed")
  vim.go.wrap = original_wrap
  vim.wo[details.window].wrap = original_wrap
  local tree = require("proud.components.tree")
  local ui = require("proud.ui")
  local conversation_cards = require("proud.loader").load("conversation_cards")
  local pane_refreshes = 0
  local card_syncs = 0
  local render_workspace = ui.render_workspace
  local sync_cards = conversation_cards.sync
  ui.render_workspace = function(...)
    pane_refreshes = pane_refreshes + 1
    return render_workspace(...)
  end
  conversation_cards.sync = function(...)
    card_syncs = card_syncs + 1
    return sync_cards(...)
  end
  local selected_id = tree.selected(state.sidebar).id
  state.sidebar.move(1)
  test.truthy(tree.selected(state.sidebar).id ~= selected_id, "selection movement updates the sidebar tree")
  test.eq(0, pane_refreshes, "selection movement does not recompose overview panes")
  test.eq(0, card_syncs, "selection movement does not synchronize conversation cards")
  tree.select(state.sidebar, "commits")
  vim.api.nvim_feedkeys("c", "x", false)
  test.eq(1, pane_refreshes, "structural sidebar changes still recompose overview panes")
  test.eq(1, card_syncs, "structural sidebar changes still synchronize conversation cards")
  ui.render_workspace = render_workspace
  conversation_cards.sync = sync_cards
  vim.cmd("silent! tabclose!")

  local session = require("proud.session")
  local credentials = require("proud.loader").load("github_credentials")
  local raw_pull = vim.json.decode([[{
    "number": 482,
    "title": "Open pull request payload",
    "user": { "login": "sara-k" },
    "state": "open",
    "milestone": null,
    "body": null,
    "head": { "ref": "feat/open-pull-request", "sha": "head-sha" },
    "base": { "ref": "main" },
    "labels": [ { "name": "runner" } ],
    "files": [ {
      "filename": "src/retry.ts",
      "status": "MODIFIED",
      "additions": 4,
      "deletions": 1,
      "patch": "@@ -1 +1 @@\n-old\n+new"
    } ],
    "commits": [ { "sha": "abc1234", "commit": { "message": "Open pull request payload" } } ],
    "statusCheckRollup": [ {
      "name": "unit",
      "conclusion": "SUCCESS",
      "duration": null
    } ]
  }]])
  local fake_client = {
    get_repository = function(_, callback)
      callback(true, { full_name = "acme/widget" })
    end,
    list_pull_requests = function(_, _, _, callback)
      callback(true, { vim.deepcopy(raw_pull) })
    end,
    get_pull_request = function(_, _, callback)
      callback(true, vim.deepcopy(raw_pull))
    end,
  }
  local token_path = vim.fn.tempname()
  session.configure({
    kind = "github",
    repository = "acme/widget",
    token = "github_pat_opening",
    token_path = token_path,
    credential = false,
    client = fake_client,
    cwd = vim.fn.getcwd(),
    -- Never check out branches in the repository running the tests.
    background_checkout = false,
  })
  session.open_pull_requests({ query = "is:open" })
  test.truthy(vim.wait(2000, function()
    return session.current and session.current.feature == "pull_request_browser"
  end, 10), "PR list opens with a provider-backed payload")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
  test.truthy(vim.wait(2000, function()
    return session.current and session.current.feature == "pull_request_overview"
  end, 10), "opening a PR reaches the overview scene")
  local overview_state = session.current.state
  test.eq(nil, overview_state.pull.milestone, "null milestone becomes an empty optional field")
  test.eq(482, overview_state.pull.number)
  local details = overview_state.workspace.panes.details
  local details_text = table.concat(vim.api.nvim_buf_get_lines(details.buffer, 0, -1, false), "\n")
  test.contains(details_text, "Milestone  none")
  test.contains(details_text, "Description")
  test.truthy(vim.api.nvim_buf_is_valid(session.current.buffer))
  vim.cmd("silent! tabclose!")
  credentials.reset()

  local delayed_callback
  local validation_callback
  local delayed_pull = vim.deepcopy(raw_pull)
  delayed_pull.number = 903
  delayed_pull.title = "Hydrated after open"
  delayed_pull.commits = { { sha = "abc1234", commit = { message = "Subject\n\nBody" } } }
  fake_client.get_repository = function(_, callback)
    validation_callback = callback
  end
  fake_client.get_pull_request = function(_, _, callback)
    delayed_callback = callback
  end
  session.configure({
    kind = "github",
    repository = "acme/widget",
    token = "github_pat_delayed",
    token_path = vim.fn.tempname(),
    credential = false,
    client = fake_client,
    cwd = vim.fn.getcwd(),
    -- Never check out branches in the repository running the tests.
    background_checkout = false,
  })
  session.open_overview(903)
  test.truthy(vim.wait(2000, function()
    return session.current
      and session.current.feature == "pull_request_overview"
      and session.current.state.pull.number == 903
  end, 10), "overview scene opens before the delayed provider callback")
  local delayed_state = session.current.state
  local tree = require("proud.components.tree")
  local sidebar_buffer = delayed_state.workspace.panes.sidebar.buffer
  vim.api.nvim_set_current_win(delayed_state.workspace.panes.sidebar.window)
  vim.api.nvim_feedkeys("jj", "x", false)
  test.eq("commits", tree.selected(delayed_state.sidebar).id, "j navigates below the three overview headers while data loads")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Space>", true, false, true), "x", false)
  test.eq(false, tree.find(delayed_state.sidebar, "commits").expanded, "space closes an empty loading header")
  delayed_state.refresh()
  local details_buffer = delayed_state.workspace.panes.details.buffer
  local loading_text = table.concat(vim.api.nvim_buf_get_lines(details_buffer, 0, -1, false), "\n")
  test.contains(loading_text, "Loading pull request details...", "overview exposes its complete placeholder UI before hydration")
  test.truthy(delayed_callback ~= nil, "provider work is requested after the UI opens")
  test.truthy(vim.wait(2000, function()
    return validation_callback ~= nil
  end, 10), "credential validation continues in the background after the scene opens")
  delayed_callback(true, delayed_pull)
  test.eq("Hydrated after open", delayed_state.pull.title, "delayed provider result hydrates the open scene")
  test.eq("commits", tree.selected(delayed_state.sidebar).id, "async hydration preserves active sidebar navigation")
  test.eq(false, tree.find(delayed_state.sidebar, "commits").expanded, "async hydration preserves sidebar collapse state")
  vim.api.nvim_feedkeys("l", "x", false)
  test.eq(true, tree.find(delayed_state.sidebar, "commits").expanded, "l opens a hydrated sidebar branch")
  vim.api.nvim_feedkeys("h", "x", false)
  test.eq(false, tree.find(delayed_state.sidebar, "commits").expanded, "h closes a hydrated sidebar branch")
  vim.api.nvim_feedkeys("l", "x", false)
  tree.select(delayed_state.sidebar, "files")
  delayed_state.refresh()
  vim.api.nvim_feedkeys("jjjj", "x", false)
  local _, selected_row = tree.row(delayed_state.sidebar)
  test.truthy(selected_row and selected_row > 3, "j reaches file entries below the three overview headers after hydration")
  test.contains(
    table.concat(vim.api.nvim_buf_get_lines(sidebar_buffer, 0, -1, false), "\n"),
    "abc1234 Subject",
    "multiline commit bodies do not crash or leak into sidebar rows"
  )
  vim.cmd("silent! tabclose!")
  credentials.reset()

  local stale_callback
  fake_client.get_pull_request = function(_, _, callback)
    stale_callback = callback
  end
  session.configure({
    kind = "github",
    repository = "acme/widget",
    token = "github_pat_stale",
    token_path = vim.fn.tempname(),
    credential = false,
    client = fake_client,
    cwd = vim.fn.getcwd(),
    -- Never check out branches in the repository running the tests.
    background_checkout = false,
  })
  session.open_overview(906)
  test.truthy(vim.wait(2000, function()
    return session.current
      and session.current.feature == "pull_request_overview"
      and session.current.state.pull.number == 906
  end, 10), "stale-callback scene opens normally")
  local stale_state = session.current.state
  vim.cmd("silent! tabclose!")
  stale_callback(true, vim.tbl_extend("force", vim.deepcopy(raw_pull), {
    number = 906,
    title = "must not hydrate closed scene",
  }))
  test.eq("Pull request #906", stale_state.pull.title, "closed scenes ignore late provider callbacks")
  credentials.reset()
end
