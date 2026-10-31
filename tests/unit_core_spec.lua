return function(test)
  local util = require("proud.util")
  local cache = require("proud.cache")
  local diff = require("proud.diff")
  local provider = require("proud.provider")
  local keymap = require("proud.keymap")
  local debounce = require("proud.debounce")
  keymap.setup({ help = "<F1>", open_diff = { "x", "X" }, quit = false })
  test.eq({ "<F1>" }, keymap.keys("help"))
  test.eq({ "x", "X" }, keymap.keys("open_diff"))
  test.eq({}, keymap.keys("quit"))
  test.eq("x / X", keymap.label("open_diff"))
  keymap.setup()
  test.eq({ "?" }, keymap.keys("help"))
  local ui = require("proud.ui")
  local render_buffer = vim.api.nvim_create_buf(false, true)
  ui.render(render_buffer, { lines = { "first\nsecond", "third\r\nfourth" } })
  test.eq({ "first second", "third fourth" }, vim.api.nvim_buf_get_lines(render_buffer, 0, -1, false), "workspace rendering flattens embedded line breaks")
  vim.api.nvim_buf_delete(render_buffer, { force = true })
  local header = ui.open_pane_header(vim.api.nvim_get_current_win(), {
    buffer_name = "proud://tests/editable-header",
    editable = true,
    prompt = "PR > ",
  })
  vim.bo[header.buffer].modifiable = true
  vim.api.nvim_buf_set_lines(header.buffer, 0, -1, false, { "PR > edited" })
  test.truthy(vim.bo[header.buffer].modified, "editable UI prompt buffers track edits normally")
  vim.api.nvim_exec_autocmds("QuitPre", {})
  test.truthy(not vim.bo[header.buffer].modified, "quit clears modified state from UI-owned prompt buffers")
  pcall(vim.api.nvim_win_close, header.window, true)
  pcall(vim.api.nvim_buf_delete, header.buffer, { force = true })
  local original_wrap = vim.go.wrap
  vim.go.wrap = false
  test.eq({ "alpha beta gamma" }, ui.wrap_text("alpha beta gamma", 12), "UI text wrapping follows disabled Neovim default")
  test.eq({ "  alpha beta gamma  " }, ui.content_lines("alpha beta gamma", { width = 12, padding = 2 }), "UI content boxes retain horizontally navigable text when Neovim wrapping is disabled")
  vim.go.wrap = true
  test.eq({ "alpha beta", "gamma" }, ui.wrap_text("alpha beta gamma", 12), "UI text wrapping follows enabled Neovim default")
  test.eq({ "alpha beta gamma" }, ui.wrap_text("alpha beta gamma", 20, { wrap = false }), "UI text wrapping can be disabled explicitly")
  test.eq({ "123", "456" }, ui.wrap_text("123456", 3), "UI text wrapping splits unbreakable tokens")
  test.eq({ "first", "", "third" }, ui.wrap_text("first\n\nthird", 20), "UI text wrapping preserves explicit line breaks")
  test.eq({ "界界", "界" }, ui.wrap_text("界界界", 4), "UI text wrapping respects display-cell width")
  local wrapped_box = ui.content_lines("alpha beta gamma", { width = 16, padding = 2 })
  test.eq(2, #wrapped_box, "UI content boxes wrap by default")
  for _, line in ipairs(wrapped_box) do
    test.eq(16, vim.fn.strdisplaywidth(line), "wrapped UI content preserves the full content-box width")
    test.eq("  ", line:sub(1, 2), "wrapped UI content preserves left padding")
    test.eq("  ", line:sub(-2), "wrapped UI content preserves right padding")
  end
  local scroll_box = ui.content_lines("alpha beta gamma", { width = 12, padding = 2, wrap = false })
  test.eq({ "  alpha beta gamma  " }, scroll_box, "explicit non-wrapped UI content remains horizontally navigable")
  local host_window = vim.api.nvim_get_current_win()
  local host_width = vim.api.nvim_win_get_width(host_window)
  local host_buffer = vim.api.nvim_win_get_buf(host_window)
  local original_host_lines = vim.api.nvim_buf_get_lines(host_buffer, 0, -1, false)
  local source = "  alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega  "
  vim.bo[host_buffer].modifiable = true
  vim.api.nvim_buf_set_lines(host_buffer, 0, -1, false, { source })
  local text_frame = ui.open_text_frame(host_window, { padding = 2 })
  local geometry = text_frame:geometry()
  test.truthy(geometry ~= nil, "UI text frames add fixed left and right margins")
  test.eq(2, geometry.padding, "UI text frame keeps the left margin width fixed")
  test.eq(0, geometry.left_col, "UI text frame pins the left margin to the viewport edge")
  test.eq(host_width - 2, geometry.right_col, "UI text frame pins the right margin to the viewport edge")
  text_frame:set_padding(1)
  geometry = text_frame:geometry()
  test.eq(1, geometry.padding, "UI text frame updates margin width")
  test.eq(host_width - 1, geometry.right_col, "UI text frame moves the right margin with its width")
  local margin_marks = vim.api.nvim_buf_get_extmarks(text_frame.buffer, text_frame.namespace, 0, 1, { details = true })
  test.eq(2, #margin_marks, "UI text frame decorates both fixed margin columns")
  local margin_columns = vim.tbl_map(function(mark)
    return mark[4].virt_text_win_col
  end, margin_marks)
  table.sort(margin_columns)
  test.eq({ 0, host_width - 1 }, margin_columns, "UI text frame anchors virtual margins in window columns")
  text_frame:set_padding(2)
  vim.api.nvim_win_set_cursor(host_window, { 1, #source - 1 })
  vim.cmd("normal! ze")
  vim.cmd("redraw")
  local screen_position = vim.fn.win_screenpos(host_window)
  local visible = {}
  for col = 1, host_width do
    visible[col] = vim.fn.screenstring(screen_position[1], screen_position[2] + col - 1)
  end
  test.eq(" ", visible[1], "horizontal navigation keeps the left margin visible")
  test.eq(" ", visible[2], "horizontal navigation keeps the complete left margin visible")
  test.eq(" ", visible[host_width - 1], "horizontal navigation keeps the complete right margin visible")
  test.eq(" ", visible[host_width], "horizontal navigation keeps the right margin visible")
  test.contains(table.concat(visible), "gamma delta", "horizontal navigation reveals complete non-wrapped text between fixed margins")
  text_frame:close()
  test.eq({}, vim.api.nvim_buf_get_extmarks(text_frame.buffer, text_frame.namespace, 0, -1, {}), "UI text frame clears its margin decoration")
  vim.bo[host_buffer].modifiable = true
  vim.api.nvim_buf_set_lines(host_buffer, 0, -1, false, original_host_lines)
  vim.bo[host_buffer].modifiable = false
  vim.api.nvim_win_call(host_window, function()
    vim.fn.winrestview({ leftcol = 0 })
  end)
  vim.go.wrap = original_wrap
  local buttons = ui.button_layout({ "One", "Two", "Three" }, 2, 40)
  test.eq(1, #buttons.lines, "default buttons render as one solid row")
  test.eq(40, vim.fn.strdisplaywidth(buttons.text), "button row fills its available width")
  test.truthy(buttons.text:find("╭", 1, true) == nil and buttons.text:find("╰", 1, true) == nil, "default buttons have no outline")
  local active_button
  local inactive_button
  for _, highlight in ipairs(buttons.highlights) do
    local value = buttons.text:sub(highlight[2] + 1, highlight[3]):gsub("^%s+", ""):gsub("%s+$", "")
    if value == "Two" then
      active_button = highlight
    elseif value == "One" then
      inactive_button = highlight
    end
  end
  test.truthy(active_button and active_button[4] == "ProudAccent", "active button uses the default solid purple fill")
  test.truthy(inactive_button and inactive_button[4] == "ProudMuted", "inactive button shares the normal background with muted text")
  test.truthy(active_button and active_button[3] - active_button[2] >= 7, "active fill includes the complete button and padding")
  local theme = require("proud.theme").groups()
  test.eq("#7F56D9", theme.ProudAccent.bg, "only the selected button receives the purple background")
  test.eq(nil, theme.ProudMuted.bg, "unselected buttons do not receive a separate background")
  local debounce_calls = {}
  local debounced = debounce.new(10, function(value)
    table.insert(debounce_calls, value)
  end)
  debounced:schedule("first")
  debounced:schedule("second")
  debounced:schedule("latest")
  test.truthy(debounced.pending(), "debounce keeps one pending timer during rapid edits")
  test.truthy(vim.wait(100, function()
    return #debounce_calls == 1
  end, 5), "debounce settles after the delay")
  test.eq({ "latest" }, debounce_calls, "debounce invokes once with the latest value")
  test.truthy(not debounced.pending(), "settled debounce is no longer pending")
  debounced:schedule("cancelled")
  debounced:cancel()
  test.truthy(not debounced.pending(), "cancelled debounce is no longer pending")
  vim.wait(30)
  test.eq({ "latest" }, debounce_calls, "cancelled debounce never calls back")
  debounced:dispose()
  test.truthy(not debounced.pending(), "disposed debounce is not pending")
  debounced:schedule("ignored")
  vim.wait(30)
  test.eq({ "latest" }, debounce_calls, "disposed debounce never schedules new work")
  local merged = util.deep_merge({
    provider = { kind = "github", cache_items = 128 },
    keymaps = { help = "?" },
  }, {
    provider = { cache_items = 2 },
    keymaps = { quit = "q" },
  })
  test.eq(2, merged.provider.cache_items)
  test.eq("github", merged.provider.kind)
  test.eq("?", merged.keymaps.help)
  test.eq("q", merged.keymaps.quit)

  local now = assert(util.parse_iso8601("2026-10-15T12:00:00Z"))
  test.eq("now", util.relative_time("2026-10-15T12:00:00Z", { now = now }), "current timestamps render as now")
  test.eq("now", util.relative_time("2026-10-15T11:59:30Z", { now = now }), "sub-minute timestamps render as now")
  test.eq("24m", util.relative_time("2026-10-15T11:36:00Z", { now = now }), "minute timestamps use compact minutes")
  test.eq("59m", util.relative_time("2026-10-15T11:01:00Z", { now = now }), "minute formatting remains below one hour")
  test.eq("1h", util.relative_time("2026-10-15T11:00:00Z", { now = now }), "hour timestamps use compact hours")
  test.eq("23h", util.relative_time("2026-10-14T13:00:00Z", { now = now }), "hour formatting remains below one day")
  test.eq("1d", util.relative_time("2026-10-14T12:00:00Z", { now = now }), "day timestamps use compact days")
  test.eq("6d", util.relative_time("2026-10-09T12:00:00Z", { now = now }), "day formatting remains below one week")
  test.eq("1w", util.relative_time("2026-10-08T12:00:00Z", { now = now }), "week timestamps use compact weeks")
  test.eq("1mo", util.relative_time("2026-09-15T12:00:00Z", { now = now }), "month timestamps use compact months")
  test.eq("1y", util.relative_time("2025-10-15T12:00:00Z", { now = now }), "year timestamps use compact years")
  test.eq("24m", util.relative_time("2026-10-15T14:36:00+03:00", { now = now }), "ISO timezone offsets are normalized")
  test.eq("2h", util.relative_time("2h"), "preformatted compact ages are preserved")

  local bounded = cache.new({ max_items = 2 })
  bounded:set("a", 1)
  bounded:set("b", 2)
  bounded:set("c", 3)
  test.eq(nil, bounded:get("a"))
  test.eq(2, bounded:get("b"))
  test.eq(3, bounded:get("c"))

  local files = diff.parse_patch(require("proud.fixtures").patch)
  test.eq(2, #files)
  test.eq(6, files[1].additions)
  test.eq(2, files[1].deletions)

  local fallback_patch = provider.build_patch_from_files({
    {
      filename = "src/retry.ts",
      status = "MODIFIED",
      patch = "@@ -1,1 +1,1 @@\n-old\n+new\n",
    },
    {
      filename = "src/config.ts",
      status = "ADDED",
      patch = "@@ -0,0 +1,2 @@\n+one\n+two\n",
    },
    {
      filename = "src/new-name.ts",
      previous_filename = "src/old-name.ts",
      status = "RENAMED",
      patch = "@@ -1,1 +1,1 @@\n-old\n+new\n",
    },
    {
      filename = "assets/logo.bin",
      status = "MODIFIED",
    },
  })
  local fallback_files = diff.parse_patch(fallback_patch)
  test.eq(4, #fallback_files, "file API fallback keeps every changed file")
  test.eq(1, fallback_files[1].additions)
  test.eq(1, fallback_files[1].deletions)
  test.eq(2, fallback_files[2].additions)
  test.eq(0, fallback_files[4].deletions)
  test.truthy(provider.is_diff_too_large({
    message = "could not find pull request diff: HTTP 406: Sorry, the diff exceeded the maximum number of lines (20000)",
  }))
  test.truthy(not provider.is_diff_too_large({ message = "HTTP 404: Not Found" }))

  local threads = provider.normalize_threads({
    {
      path = "src/retry.ts",
      line = 12,
      user = { login = "dev-lee" },
      body = "first comment",
    },
    {
      path = "src/retry.ts",
      line = 12,
      user = { login = "sara-k" },
      body = "reply",
    },
    {
      path = "src/config.ts",
      line = 9,
      user = { login = "dev-lee" },
      body = "second thread",
    },
  })
  test.eq(2, #threads, "comments at one location form one thread")
  test.eq(2, #threads[1].comments)
  test.eq("dev-lee", threads[1].comments[1].author)
  test.eq("src/config.ts", threads[2].path)

  local pull = provider.normalize_pull_request({
    number = 482,
    title = "Add retry",
    author = { login = "sara-k" },
    milestone = { title = "Q4" },
    labels = { { name = "runner" }, { name = "reliability" } },
    headRefName = "feat/retry",
    baseRefName = "main",
    reviewDecision = "CHANGES_REQUESTED",
    isDraft = false,
    files = {
      { path = "retry.ts", status = "MODIFIED", additions = 2, deletions = 1 },
    },
    commits = {
      { oid = "a3f91c2", messageHeadline = "Use config for retry limits" },
    },
    statusCheckRollup = {
      {
        name = "lint",
        conclusion = "SUCCESS",
        started_at = "2026-10-18T12:00:00Z",
        completed_at = "2026-10-18T12:00:18Z",
      },
      { name = "e2e / robot-studio", conclusion = "FAILURE", duration = "6m 40s" },
    },
    check_errors = {
      { source = "merge_statuses", code = 502, message = "temporary status failure" },
    },
  })
  test.eq("sara-k", pull.author)
  test.eq("Q4", pull.milestone)
  test.eq("runner", pull.labels[1])
  test.eq("feat/retry", pull.head_ref)
  test.eq("CHANGES_REQUESTED", pull.review_decision)
  test.eq(false, pull.is_draft)
  test.eq("M", pull.files[1].status)
  test.eq("a3f91c2", pull.commits[1].sha)
  test.eq("Use config for retry limits", pull.commits[1].message)
  local multiline_commit = provider.normalize_pull_request({
    commits = {
      { sha = "abc1234", commit = { message = "Commit subject\n\nDetailed body" } },
      { sha = "def5678", message = "REST subject\nREST body", messageHeadline = "Preferred subject" },
    },
  })
  test.eq("Commit subject", multiline_commit.commits[1].message, "REST commit messages render only their subject")
  test.eq("Preferred subject", multiline_commit.commits[2].message, "GraphQL commit headlines take precedence over full messages")
  test.eq("pass", pull.checks[1].status)
  test.eq("fail", pull.checks[2].status)
  test.eq("18s", pull.checks[1].duration, "provider formats check-run timestamps")
  test.eq("6m 40s", pull.checks[2].duration, "provider preserves explicit check durations")
  test.eq("temporary status failure", pull.check_errors[1].message, "provider preserves partial check-source errors")
  local wrapped_checks = provider.normalize_checks({
    total_count = 1,
    check_runs = { { name = "wrapped", conclusion = "SUCCESS" } },
  })
  test.eq("wrapped", wrapped_checks[1].name, "provider accepts GitHub's wrapped check-run collection")

  local metadata_now = assert(util.parse_iso8601("2026-10-15T12:00:00Z"))
  local metadata_pull = provider.normalize_pull_request({
    number = 991,
    title = "Metadata normalization",
    body = "## Summary\nUse the bounded retry budget.\n\n## Testing\n- [x] unit\n",
    labels = { nodes = { { name = "api-label" }, { name = "performance" } } },
    requestedReviewers = { nodes = { { login = "pending-reviewer" } } },
    latestReviews = { nodes = {
      {
        id = 77,
        author = { login = "changes-reviewer" },
        state = "CHANGES_REQUESTED",
        submittedAt = "2026-10-15T11:00:00Z",
        body = "Cap the retry delay.",
      },
      {
        author = { login = "approved-reviewer" },
        state = "APPROVED",
        submittedAt = "2026-10-15T10:00:00Z",
        body = "Looks good.",
      },
    } },
    comments = {
      {
        id = 88,
        in_reply_to_id = 77,
        user = { login = "comment-author" },
        created_at = "2026-10-15T11:36:00Z",
        body = "The API summary comment.",
      },
    },
    review_comments = {
      {
        id = 89,
        pull_request_review_id = 77,
        user = { login = "inline-reviewer" },
        created_at = "2026-10-15T11:20:00Z",
        body = "This condition is inverted.",
      },
      {
        id = 90,
        in_reply_to_id = 89,
        user = { login = "inline-author" },
        created_at = "2026-10-15T11:25:00Z",
        body = "Fixed in the next push.",
      },
    },
  }, { now = metadata_now })
  test.eq({ "api-label", "performance" }, metadata_pull.labels, "label connections keep API order and names")
  test.eq({
    { id = "77", login = "changes-reviewer", state = "changes_requested", age = "1h", body = "Cap the retry delay." },
    { login = "approved-reviewer", state = "approved", age = "2h", body = "Looks good." },
    { login = "pending-reviewer", state = "pending", age = "", body = "" },
  }, metadata_pull.reviewers, "review decisions and pending requests normalize into one reviewer list")
  test.eq("comment-author", metadata_pull.comments[1].author)
  test.eq("24m", metadata_pull.comments[1].age)
  test.eq("77", metadata_pull.comments[1].reply_to_id, "provider preserves comment reply links")
  test.eq("inline-reviewer", metadata_pull.comments[2].author)
  test.eq("77", metadata_pull.comments[2].reply_to_id, "review comments link to their review")
  test.eq("inline-author", metadata_pull.comments[3].author)
  test.eq("89", metadata_pull.comments[3].reply_to_id, "review comment replies link to their parent comment")
  test.contains(metadata_pull.body, "Use the bounded retry budget.", "API body remains the description source")

  local rest_now = assert(util.parse_iso8601("2026-10-15T12:00:00Z"))
  local rest_pull = provider.normalize_pull_request({
    number = 6665,
    title = "Large diff",
    user = { login = "api-author" },
    state = "open",
    draft = true,
    created_at = "2026-10-15T00:00:00Z",
    html_url = "https://github.com/acme/widget/pull/6665",
    head = { ref = "feat/api", sha = "head-sha" },
    base = { ref = "main" },
    files = {
      { filename = "src/api.ts", status = "modified", additions = 3, deletions = 1 },
    },
    commits = {
      { sha = "commit-sha", commit = { message = "Use API" } },
    },
    statusCheckRollup = {
      { name = "api-e2e", conclusion = "success" },
    },
  }, { now = rest_now })
  test.eq("api-author", rest_pull.author)
  test.eq("feat/api", rest_pull.head_ref)
  test.eq("head-sha", rest_pull.head_sha)
  test.eq("main", rest_pull.base_ref)
  test.eq(true, rest_pull.is_draft)
  test.eq("Open", rest_pull.state)
  test.eq("12h", rest_pull.age, "raw API timestamps normalize into relative age")
  test.eq("M", rest_pull.files[1].status)
  test.eq("Use API", rest_pull.commits[1].message)
  test.eq("pass", rest_pull.checks[1].status)
end
