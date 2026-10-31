return function(test)
  local feature = require("proud.loader").load("pull_request_browser")
  local fixtures = require("proud.fixtures")
  local state = feature.create(fixtures.pull_requests, { query = "author:sara-k retry" })
  test.eq(1, #state.filtered, "author and text filters combine")
  test.eq(482, feature.selected(state).number)
  feature.move(state, 1)
  test.eq(1, state.cursor, "cursor remains in range")
  feature.set_query(state, "label:capture")
  test.eq(479, feature.selected(state).number)
  local counts = feature.counts(state)
  test.eq(1, counts.filtered, "filtered count tracks the visible pull requests")
  test.eq(#fixtures.pull_requests, counts.total, "total count tracks every source pull request")
  test.eq("1/" .. #fixtures.pull_requests, feature.count_label(state), "count label formats filtered/total")
  local view = feature.render_list(state, { width = 50 })
  test.truthy(not table.concat(view.lines, "\n"):find("PRs ❯", 1, true), "query lives in the native header, not the body")
  test.highlighted(view, "#479", "ProudAccentText", "PR number is purple")
  test.highlighted(view, "Fix Capture", "ProudBright", "PR title is bright")
  test.highlighted(view, "●", "ProudSuccessText", "open PR status circle is successful")
  test.highlighted(view, "dev-lee", "ProudMuted", "author is muted metadata")
  test.contains(view.lines[2], "dev-lee · 5h · +58-22 · 1 thread · Review request", "subtitle uses the requested dot-separated format")
  test.highlighted(view, "+58", "ProudSuccessText", "additions use success color")
  test.highlighted(view, "-22", "ProudDangerText", "deletions use danger color")
  test.highlighted(view, "1 thread", "ProudWarning", "thread count is warning-colored")
  test.highlighted(view, "Review request", "ProudAccentText", "review state is accented")
  test.truthy(not view.lines[2]:find("◆", 1, true), "thread count uses words rather than a symbol")
  test.matches(view.lines[1], "^▌", "selected title uses the left cursor rail")
  test.matches(view.lines[2], "^▌", "selected subtitle directly follows the title")
  test.truthy(not view.lines[3]:find("▌", 1, true), "the next PR starts without an inter-item spacer")
  test.highlighted(view, "▌", "ProudAccentText", "cursor rail is purple")
  local function has_full_row_group(row, group)
    for index = 1, #(view.highlights or {}), 4 do
      if view.highlights[index] == row - 1
        and view.highlights[index + 1] == 0
        and view.highlights[index + 2] == #view.lines[row]
        and view.highlights[index + 3] == group
      then
        return true
      end
    end
    return false
  end
  test.truthy(has_full_row_group(1, "ProudSelection"), "selected title row has a subtle shade")
  test.truthy(has_full_row_group(2, "ProudSelection"), "selected subtitle row shares the shade")
  test.truthy(not has_full_row_group(3, "ProudSelection"), "unselected rows have the shared base background")
  for _, line in ipairs(view.lines) do
    test.eq(50, vim.fn.strdisplaywidth(line), "browser rows are straight at the window width")
    test.truthy(not line:find("╭", 1, true) and not line:find("╰", 1, true), "native windows draw the rounded border")
  end
  local narrow_view = feature.render_list(state, { width = 30 })
  for _, line in ipairs(narrow_view.lines) do
    test.eq(30, vim.fn.strdisplaywidth(line), "browser rows are straight at narrow widths")
  end
  test.contains(narrow_view.lines[2], "+58-22·1 thread·review", "narrow subtitles keep diff, thread, and review state")

  local no_threads_state = feature.create({ fixtures.pull_requests[3] }, { query = "" })
  local no_threads_view = feature.render_list(no_threads_state, { width = 54 })
  test.contains(no_threads_view.lines[2], "amir-r · 1d · +201-40 · no threads · Review request", "zero threads renders as no threads")

  local plural_state = feature.create({ fixtures.pull_requests[1] }, { query = "" })
  local plural_view = feature.render_list(plural_state, { width = 54 })
  test.contains(plural_view.lines[2], "sara-k · 2h · +134-17 · 3 threads · changes requested", "multiple threads use plural wording")

  local provider = require("proud.provider")
  local raw_pulls = {}
  for index, count in ipairs({ 3, 1, 0 }) do
    table.insert(raw_pulls, provider.normalize_pull_request({
      number = 900 + index,
      title = "Raw review thread count " .. index,
      author = { login = "api-author-" .. index },
      age = "2h",
      additions = 77,
      deletions = 9,
      reviewDecision = "REVIEW_REQUIRED",
      labels = { nodes = { { name = "api" } } },
      reviewThreads = { totalCount = count },
    }))
  end
  local raw_thread_state = feature.create(raw_pulls, { query = "" })
  local raw_thread_view = feature.render_list(raw_thread_state, { width = 64 })
  test.eq({ 3, 1, 0 }, {
    raw_pulls[1].threads,
    raw_pulls[2].threads,
    raw_pulls[3].threads,
  }, "raw reviewThreads totals normalize into thread counts")
  test.eq({ 77, 9 }, { raw_pulls[1].additions, raw_pulls[1].deletions }, "raw diff totals normalize into additions and deletions")
  test.eq({ "api" }, raw_pulls[1].labels, "GraphQL label connections normalize into label names")
  test.eq("REVIEW_REQUIRED", raw_pulls[1].review_decision, "GraphQL review decisions normalize into the browser contract")
  test.contains(raw_thread_view.lines[2], "3 threads", "raw reviewThreads.totalCount=3 becomes plural threads")
  test.contains(raw_thread_view.lines[4], "1 thread", "raw reviewThreads.totalCount=1 becomes singular thread")
  test.contains(raw_thread_view.lines[6], "no threads", "raw reviewThreads.totalCount=0 becomes no threads")

  local util = require("proud.util")
  local relative_now = assert(util.parse_iso8601("2026-10-15T12:00:00Z"))
  local relative_pulls = {}
  for index, created_at in ipairs({
    "2026-10-15T11:36:00Z",
    "2026-10-15T11:00:00Z",
    "2026-10-14T12:00:00Z",
  }) do
    table.insert(relative_pulls, provider.normalize_pull_request({
      number = 910 + index,
      title = "Relative timestamp " .. index,
      author = { login = "time-author-" .. index },
      createdAt = created_at,
      additions = 7,
      deletions = 2,
      reviewDecision = "REVIEW_REQUIRED",
      reviewThreads = { totalCount = 0 },
    }, { now = relative_now }))
  end
  local relative_view = feature.render_list(feature.create(relative_pulls, { query = "" }), { width = 64 })
  test.contains(relative_view.lines[2], " · 24m · ", "24-minute API timestamps render compactly")
  test.contains(relative_view.lines[4], " · 1h · ", "one-hour API timestamps render compactly")
  test.contains(relative_view.lines[6], " · 1d · ", "one-day API timestamps render compactly")

  local ui = require("proud.ui")
  local groups = require("proud.theme").groups()
  test.eq("#101828", groups.ProudBackground.bg, "base content background is dark")
  test.eq("#253347", groups.ProudSelection.bg, "only selected rows use the lighter shade")
  local source_state = feature.create({}, {})
  test.eq(3, source_state.source_index, "All open is the default PR source")
  feature.set_source(source_state, 1)
  test.eq("is:open review-requested:@me", source_state.query, "source tabs map to PR list queries")
  local selector_view = ui.button_layout(feature.sources(), 3, 80)
  test.eq(80, vim.fn.strdisplaywidth(selector_view.text), "source selector fills a straight line")
  test.truthy(selector_view.text:find("  All open  ", 1, true) ~= nil, "selected source has larger button padding")
  for _, label in ipairs({ "Review requested", "Mine", "All open", "Recently viewed", "Branches" }) do
    test.contains(selector_view.text, label, "source selector includes " .. label)
  end
  local selected_group
  local muted_group
  for _, highlight in ipairs(selector_view.highlights) do
    local value = selector_view.text:sub(highlight[2] + 1, highlight[3]):gsub("^%s+", ""):gsub("%s+$", "")
    if value == "All open" then
      selected_group = highlight[4]
    elseif value == "Mine" then
      muted_group = highlight[4]
    end
  end
  test.eq("ProudAccent", selected_group, "selected source uses purple with white text")
  test.eq("ProudMuted", muted_group, "unselected sources share the normal background")
  local original_layout = ui.layout_config()
  test.eq(3, original_layout.gap, "default window gap separates the native panes")
  local configured_layout = ui.configure({
    windows = {
      margin = { top = 4, bottom = 5, left = 6, right = 7 },
      gap = 5,
    },
  })
  test.eq({ top = 4, bottom = 5, left = 6, right = 7 }, configured_layout.margin, "window margins are configurable")
  test.eq(5, configured_layout.gap, "window gap is configurable")
  ui.configure(original_layout)

  local count_pulls = {}
  for index = 1, 14 do
    table.insert(count_pulls, {
      number = 6000 + index,
      title = "Count verification " .. index,
      author = { login = "count-author" },
      labels = index <= 8 and { "capture" } or { "other" },
    })
  end
  local count_state = feature.create(count_pulls, { query = "label:capture", total_count = 14 })
  test.eq({ filtered = 8, total = 14 }, feature.counts(count_state), "count state reports eight filtered from fourteen total")
  test.eq("8/14", feature.count_label(count_state), "count label matches the requested format")

  local metadata_pull = provider.normalize_pull_request({
    number = 731,
    title = "Use bounded retry budget",
    body = "API description first message from the pull request body.\n\n## Testing\n- [x] unit\nFinal description line for complete rendering.",
    labels = { nodes = { { name = "api-label" }, { name = "performance" } } },
    requestedReviewers = { nodes = { { login = "pending-reviewer" } } },
    latestReviews = { nodes = {
      {
        author = { login = "changes-reviewer" },
        state = "CHANGES_REQUESTED",
        submittedAt = "2026-10-15T11:00:00Z",
      },
    } },
  })
  local metadata_view = feature.render_preview(feature.create({ metadata_pull }, { query = "" }), { width = 82 })
  local metadata_text = table.concat(metadata_view.lines, "\n")
  test.contains(metadata_text, "changes-reviewer changes requested", "preview uses the API review decision")
  test.contains(metadata_text, "pending-reviewer review pending", "preview uses requested reviewers from the API")
  test.contains(metadata_text, "Labels     api-label · performance", "preview uses the exact API labels")
  test.contains(metadata_text, "API description first message from the pull request body.", "preview shows the first PR message")
  test.contains(metadata_text, "Final description line for complete rendering.", "preview keeps the complete PR description")
  test.truthy(not metadata_text:find("## Summary", 1, true), "preview does not generate a Summary section")
  test.truthy(not metadata_text:find("dev-lee", 1, true), "preview does not leak fixture reviewers")
  test.truthy(not metadata_text:find("Exponential retry", 1, true), "preview does not leak fixture summary text")

  local long_body = {}
  for index = 1, 30 do
    table.insert(long_body, ("description line %d for preview scrolling"):format(index))
  end
  local long_pull = provider.normalize_pull_request({
    number = 732,
    title = "Long pull request description",
    body = table.concat(long_body, "\n"),
  })
  local long_view = feature.render_preview(feature.create({ long_pull }, { query = "" }), { width = 72 })
  local long_text = table.concat(long_view.lines, "\n")
  test.contains(long_text, "description line 1 for preview scrolling", "long description starts with its first message line")
  test.contains(long_text, "description line 30 for preview scrolling", "long description retains lines below the viewport")

  test.eq(1, feature.page_size_for_height(3), "three list rows show one two-row pull request")
  test.eq(1, feature.page_size_for_height(5), "header rows are removed before dividing by item height")
  test.eq(2, feature.page_size_for_height(6), "six list rows show two two-row pull requests")
  test.eq(7, feature.page_size_for_height(16), "sixteen list rows show seven complete pull requests")
  local prefetch_state = feature.create({ { number = 1, title = "One" } }, { query = "" })
  feature.move(prefetch_state, 1)
  test.truthy(prefetch_state.cursor_moved, "selection movement enables two-page prefetch")
  test.eq(2, prefetch_state.prefetch_pages, "browser keeps two additional pages ready")

  local page_state = feature.create({}, { query = "" })
  feature.apply_page(page_state, {
    pulls = {
      { number = 1, title = "First page one" },
      { number = 2, title = "First page two" },
    },
    total_count = 5,
    has_next_page = true,
    next_cursor = "page-2",
  }, { replace = true })
  test.eq(2, #page_state.pulls, "the first request keeps only its visible page")
  test.eq(5, page_state.total_count, "pagination preserves the complete source count")
  test.eq("page-2", page_state.next_cursor, "pagination keeps the next GraphQL cursor")
  feature.apply_page(page_state, {
    pulls = {
      { number = 2, title = "Duplicate" },
      { number = 3, title = "Second page one" },
    },
    total_count = 5,
    has_next_page = true,
    next_cursor = "page-3",
  })
  test.eq(3, #page_state.pulls, "the next page appends only unseen pull requests")
  test.eq("Second page one", page_state.pulls[3].title)

  local lazy_pull = provider.normalize_pull_request({
    number = 733,
    title = "Lazy first message",
  })
  local lazy_view = feature.render_preview(feature.create({ lazy_pull }, { query = "" }), { width = 60 })
  test.contains(table.concat(lazy_view.lines, "\n"), "Loading description...", "unfetched descriptions do not render placeholder content as body")
  lazy_pull.body = "Loaded only for the selected pull request."
  lazy_pull.description_loaded = true
  local loaded_view = feature.render_preview(feature.create({ lazy_pull }, { query = "" }), { width = 60 })
  test.contains(table.concat(loaded_view.lines, "\n"), "Loaded only for the selected pull request.")
end
