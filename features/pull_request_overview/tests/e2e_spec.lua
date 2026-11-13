return function(test)
  local feature = require("proud.loader").load("pull_request_overview")
  local polling = feature.create({ number = 46, checks = {
    { id = "ci", name = "CI", status = "pending", target_url = "https://example.com/ci" },
  } })
  local calls, reply, opened = 0, nil, nil
  feature.open(polling, {
    check_refresh_ms = 10,
    on_check = function(url) opened = url end,
    on_refresh_checks = function(done) calls = calls + 1; reply = done end,
  })
  local tree = require("proud.components.tree")
  tree.select(polling.sidebar, "check:ci:1")
  require("proud.loader").load("sidebar").sync_cursor(polling.sidebar, polling.workspace.panes.sidebar.window)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
  test.eq("https://example.com/ci", opened, "Enter opens check details")
  test.truthy(vim.wait(1000, function() return calls == 1 end, 5), "pending checks are polled")
  vim.wait(35, function() return false end, 5)
  test.eq(1, calls, "poll requests cannot overlap")
  vim.cmd("tabnew")
  reply(false, { message = "offline" })
  vim.wait(35, function() return false end, 5)
  test.eq(1, calls, "hidden overviews pause polling")
  vim.cmd("tabclose")
  test.eq("pending", polling.checks[1].status, "refresh failures retain last checks")
  test.truthy(vim.wait(1000, function() return calls == 2 end, 5), "failed polls retry")
  polling.drafts = { new = "keep my draft" }
  polling.files = { { path = "a", viewed = true } }
  local details = polling.workspace.panes.details
  local before = vim.api.nvim_buf_get_lines(details.buffer, 0, -1, false)
  reply(true, { { id = "ci", name = "CI", conclusion = "SUCCESS" } })
  test.eq("pass", polling.checks[1].status)
  test.eq(before, vim.api.nvim_buf_get_lines(details.buffer, 0, -1, false), "check refresh leaves details unchanged")
  test.eq("keep my draft", polling.drafts.new)
  test.truthy(polling.files[1].viewed)
  test.truthy(polling.check_timer:is_closing(), "completed checks stop the timer")
  require("proud.ui").close_workspace(polling.workspace)
  local closing = feature.create({ number = 47, checks = { { name = "CI", status = "pending" } } })
  local late
  feature.open(closing, { check_refresh_ms = 10, on_refresh_checks = function(done) late = done end })
  test.truthy(vim.wait(1000, function() return late ~= nil end, 5))
  require("proud.ui").close_workspace(closing.workspace)
  test.truthy(closing.check_timer:is_closing(), "closing the overview closes its timer")
  late(true, { { name = "CI", status = "pass" } })
  test.eq("pending", closing.checks[1].status, "late responses cannot mutate a closed overview")
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

  -- Conversation: ]] / [[ walk the description and each card; r replies,
  -- c comments, in an editor in the conversation (design screen 2).
  local function press(value)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(value, true, false, true), "x", false)
  end
  local talk = vim.deepcopy(fixtures.overview)
  talk.review_comments = {
    { id = 301, reply_to_id = "100", reply_to_kind = "review", author = "dev-lee", age = "1h", body = "attempt is already incremented here." },
    { id = 302, in_reply_to_id = 301, author = "sara-k", age = "40m", body = "Fixing in the next push." },
  }
  local posts = {}
  local answer = { true }
  local talk_state = feature.create(talk)
  feature.open(talk_state, {
    viewer = function() return "morteza" end,
    on_comment = function(kind, root, body, done)
      posts[#posts + 1] = { kind = kind, root = root, body = body }
      local ok = answer[1]
      vim.schedule(function()
        done(ok, ok and { id = 900 + #posts, author = "morteza", body = body } or { message = "HTTP 403: Resource not accessible" })
      end)
    end,
  })
  local details = ui.workspace_window(talk_state.workspace, "details")
  vim.api.nvim_set_current_win(details)
  vim.api.nvim_win_set_cursor(details, { 1, 0 })
  press("]]")
  test.eq("description", talk_state.focused, "]] goes to the description first")
  press("]]")
  test.eq("review:100", talk_state.focused, "then to the first conversation item")
  test.eq("review:100", talk_state.comment_card_windows.selected_id, "the focused card is selected")
  local focused_card = talk_state.comment_card_windows.cards["review:100"]
  test.contains(vim.wo[focused_card.window].winhighlight, "FloatBorder:ProudCardBorderSelected", "with an accent border")
  press("]]")
  test.eq("comment:201", talk_state.focused, "replies are items too")
  press("]]")
  test.eq("review_comment:301", talk_state.focused, "and inline review comments")
  press("[[")
  press("[[")
  test.eq("review:100", talk_state.focused, "[[ goes back")
  local card_line = vim.api.nvim_win_get_cursor(details)[1]
  press("j")
  test.eq("review:100", talk_state.focused, "moving inside a card keeps it focused")
  vim.api.nvim_win_set_cursor(details, { card_line, 0 })

  -- The comment box is always at the end, like the design.
  local box = talk_state.comment_card_windows.specs[#talk_state.comment_card_windows.specs]
  test.eq("comment_box", box.id, "the comment box ends the conversation")
  test.contains(table.concat(box.lines, "\n"), "Comment  · markdown", "with the design's header")
  test.contains(table.concat(box.lines, "\n"), "Leave a comment on the PR", "and its placeholder")

  -- r on a review quotes it into a new PR comment (GitHub has no threads
  -- for those).
  press("r")
  local editor = talk_state.editor
  test.truthy(editor and not editor.closed, "r opens the editor")
  test.eq(editor.window, vim.api.nvim_get_current_win(), "focused")
  test.eq("new", editor.target, "a review is answered with a new PR comment")
  test.eq("markdown", vim.bo[editor.buffer].filetype, "in markdown")
  test.contains(table.concat(vim.api.nvim_buf_get_lines(editor.buffer, 0, -1, false), "\n"), "> Backoff math is off by one", "quoting it")
  test.truthy(vim.fn.maparg("@", "i", false, true).buffer == 1, "@ completes mentions")
  test.truthy(vim.tbl_contains(feature.participants(talk_state), "dev-lee"), "from the conversation")
  local editor_row = vim.api.nvim_win_get_config(editor.window).row
  local slot
  for _, spec in ipairs(talk_state.conversation_cards) do
    if spec.slot then slot = spec end
  end
  test.truthy(slot ~= nil, "the conversation makes room for the editor")
  local topline = vim.api.nvim_win_call(details, function() return vim.fn.winsaveview().topline end)
  test.eq(slot.row - topline, editor_row, "the editor sits in that room")
  press("<Esc>")
  test.truthy(editor.closed, "<Esc> closes the editor")
  test.eq(details, vim.api.nvim_get_current_win(), "focus returns to the overview")
  test.eq("comment_box", talk_state.focused, "on the comment box")
  test.contains(talk_state.drafts.new or "", "> Backoff math", "keeping the draft")
  box = talk_state.comment_card_windows.specs[#talk_state.comment_card_windows.specs]
  test.contains(table.concat(box.lines, "\n"), "Backoff math", "the comment box shows the draft")

  -- c reopens the draft; <C-s> posts it.
  press("c")
  editor = talk_state.editor
  test.contains(editor.text(), "> Backoff math", "c restores the draft")
  press("<C-s>")
  test.truthy(vim.wait(1000, function() return editor.closed end, 10), "posting closes the editor")
  test.eq("comment", posts[1].kind, "a PR comment is posted")
  test.eq(nil, talk_state.drafts.new, "the posted draft is cleared")
  test.eq("comment:901", talk_state.focused, "the cursor lands on the new comment")
  test.contains(table.concat(talk_state.comment_card_windows.specs[#talk_state.comment_card_windows.specs - 1].lines, "\n"), "morteza", "which shows in the conversation")

  -- r on an inline review comment replies in its thread, under it.
  local go_item
  for _, item in ipairs(talk_state.items) do
    if item.id == "review_comment:302" then
      go_item = item
    end
  end
  talk_state.go_to(go_item)
  press("r")
  editor = talk_state.editor
  test.eq("review_comment:301", editor.target, "the reply goes to the thread's first comment")
  local reply_slot
  for index, spec in ipairs(talk_state.conversation_cards) do
    if spec.slot then
      reply_slot = spec
      test.eq("review_comment:302", talk_state.conversation_cards[index - 1].id, "the editor sits at the end of the thread")
    end
  end
  test.truthy(reply_slot.depth > 0, "indented like a reply")
  test.eq(" Reply to dev-lee", vim.api.nvim_win_get_config(editor.window).title[1][1], "titled with who it answers")

  -- A failed post keeps the editor and the text, and says why.
  answer = { false }
  local notify = vim.notify
  local notified
  vim.notify = function(message) notified = message end
  press("aWill do<C-s>")
  test.truthy(vim.wait(1000, function() return notified ~= nil end, 10), "the error is reported")
  vim.notify = notify
  test.contains(notified, "HTTP 403", "with GitHub's message")
  test.truthy(not editor.closed, "the editor stays open")
  test.eq("Will do", editor.text(), "the text is kept")
  test.contains(vim.api.nvim_win_get_config(editor.window).footer[1][1], "Could not post", "the footer shows it")
  answer = { true }
  press("<C-s>")
  test.truthy(vim.wait(1000, function() return editor.closed end, 10), "posting again works")
  test.eq("reply", posts[#posts].kind, "as a threaded reply")
  test.eq("301", posts[#posts].root.source_id, "to comment 301")
  local reply_entry = talk_state.entries["review_comment:" .. tostring(900 + #posts)]
  test.truthy(reply_entry ~= nil and reply_entry.parent ~= nil, "the reply joins the thread")

  -- Empty comments are not posted; closing the scene keeps the draft.
  local count = #posts
  press("c")
  press("<C-s>")
  test.eq(count, #posts, "empty comments are not posted")
  test.contains(vim.api.nvim_win_get_config(talk_state.editor.window).footer[1][1], "Write something first.", "and say why")
  press("aunsent")
  vim.cmd("stopinsert")
  vim.cmd("silent! tabclose!")
  test.eq("unsent", talk_state.drafts.new, "closing the overview keeps the draft")

  -- Through the session: comments post to GitHub's issue comments and
  -- inline replies to the review comment replies endpoint.
  local requests = {}
  fake_client.post_issue_comment = function(_, number, body, callback)
    requests[#requests + 1] = { "comment", number, body }
    callback(true, { id = 77, user = { login = "morteza" }, body = body })
  end
  fake_client.reply_to_review_comment = function(_, number, comment_id, body, callback)
    requests[#requests + 1] = { "reply", number, comment_id, body }
    callback(true, { id = 78, user = { login = "morteza" }, body = body, created_at = "2026-01-01T00:00:00Z" })
  end
  local act = session.comment_action(482)
  local results = {}
  act("comment", nil, "Looks good", function(ok, value) results[1] = { ok, value } end)
  act("reply", { source_id = "301" }, "Done", function(ok, value) results[2] = { ok, value } end)
  test.truthy(vim.wait(1000, function() return results[2] ~= nil end, 10), "both post")
  test.eq({ "comment", 482, "Looks good" }, requests[1], "a comment posts to the PR's issue comments")
  test.eq({ "reply", 482, "301", "Done" }, requests[2], "a reply posts to the thread's first comment")
  test.eq(77, results[1][2].id, "returning the new comment")
  test.eq("morteza", results[1][2].author)
  credentials.reset()
end
