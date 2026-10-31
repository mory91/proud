return function(test)
  local feature = require("proud.loader").load("pull_request_overview")
  local fixtures = require("proud.fixtures")
  local state = feature.create(fixtures.overview)
  test.eq(1, feature.viewed_count(state))
  test.truthy(feature.mark_viewed(state, "packages/runner/src/task/retry.ts"))
  test.eq(2, feature.viewed_count(state))
  local view = feature.render(state)
  test.contains(table.concat(view.lines, "\n"), "Description")
  test.contains(table.concat(view.lines, "\n"), "e2e in robot studio")
  test.truthy(not table.concat(view.lines, "\n"):find("<CR>", 1, true), "overview does not print keyboard legends")
  local panes = feature.render_panes(state)
  test.contains(table.concat(panes.sidebar.lines, "\n"), "Checks 4 of 5 passing")
  test.highlighted(panes.sidebar, "Files", "ProudBright", "file section label is white")
  test.highlighted(panes.sidebar, "5 · 1 of 5 viewed", "ProudMuted", "file section metadata is grey")
  test.highlighted(panes.sidebar, "a3f91c2", "ProudAccentText", "commit IDs are accented")
  test.highlighted(panes.sidebar, "✓", "ProudSuccessText", "passing checks are successful")
  test.highlighted(panes.sidebar, "✗", "ProudDangerText", "failed checks are dangerous")
  test.highlighted(panes.details, "── Description", "ProudMuted", "description separator is grey")
  test.highlighted(panes.details, "── Conversation 2", "ProudMuted", "conversation separator is grey")
  local cards = view.conversation_cards
  test.eq(2, #cards, "overview lays out one native card per conversation entry")
  test.contains(table.concat(cards[1].lines, "\n"), "dev-lee  reviewed  change requested  · 1h ago")
  test.contains(table.concat(cards[1].lines, "\n"), "Backoff math is off by one in retry.ts.")
  test.contains(table.concat(cards[2].lines, "\n"), "sara-k  commented  · 40m ago")
  test.contains(table.concat(cards[2].lines, "\n"), "Good catch. Pushing a fix in the next commit.")
  test.truthy(cards[2].row > cards[1].row, "reply cards render under their root")
  test.truthy(cards[2].col > cards[1].col, "reply cards are visually nested")
  test.truthy(not table.concat(view.lines, "\n"):find("╭", 1, true), "overview buffer does not draw card border characters")
  test.truthy(not table.concat(view.lines, "\n"):find("│", 1, true), "overview buffer does not draw card separators")
  test.eq(2, view.padding, "overview uses symmetric horizontal content padding")
  for _, line in ipairs(view.lines) do
    test.eq("  ", line:sub(1, 2), "overview content starts after the left padding")
    test.eq("  ", line:sub(-2), "overview content ends before the right padding")
  end
  test.eq(2, cards[1].col, "root cards start after the left padding")
  test.truthy(cards[1].col + cards[1].width + 2 <= 78, "root cards stop before the right padding")
  local card_text = table.concat(cards[1].lines, "\n")
  local card_view = {
    lines = cards[1].lines,
    highlights = cards[1].highlights,
    highlight_format = "structured",
  }
  test.contains(card_text, "dev-lee")
  test.highlighted(card_view, "dev-lee", "ProudAccentText", "comment author is accented")
  test.highlighted(card_view, "1h ago", "ProudMuted", "comment age is grey")
  test.highlighted(card_view, "change requested", "ProudWarning", "change-requested metadata uses warning color")
  for _, width in ipairs({ 72, 120 }) do
    local sized = feature.render(state, width)
    test.truthy(#sized.conversation_cards == 2, "native card layout survives terminal width " .. width)
    test.truthy(sized.conversation_cards[1].col + sized.conversation_cards[1].width + 2 <= width - 2, "root cards fit inside the padded details pane")
  end

  local constrained_state = feature.create({
    number = 483,
    title = "A deliberately long title with many ordinary words that must stay inside both overview margins at every rendered width",
    author = "dev-lee",
    state = "Open",
    head_ref = "feat/very-long-reviewer-branch-name-that-also-uses-the-full-available-content-box",
    base_ref = "main",
    labels = { "a", "b", "c", "d", "e", "f", "g" },
    milestone = "A milestone name long enough to wrap within the overview content box",
    reviewers = { { login = "reviewer-with-a-long-account-name", state = "changes_requested" } },
    body = {
      "This description paragraph is deliberately long so it wraps within the two-column content margins rather than crossing the right edge.",
      "## A very long Markdown heading should remain inside the same constrained text box and retain its heading emphasis",
      "- [x] " .. string.rep("unbreakable-token-", 10),
    },
  })
  local constrained = feature.render(constrained_state, 60)
  test.truthy(#constrained.lines > 12, "long overview content wraps into multiple constrained lines")
  local constrained_text = table.concat(constrained.lines, "\n")
  test.contains(constrained_text, "deliberately long", "wrapped description text remains readable")
  test.contains(constrained_text, "unbreakable-token-", "unbreakable tokens are split inside the content box")
  for index, line in ipairs(constrained.lines) do
    test.eq(60, vim.fn.strdisplaywidth(line), "overview line " .. index .. " preserves two-column margins")
    test.eq("  ", line:sub(1, 2), "overview line " .. index .. " preserves left padding")
    test.eq("  ", line:sub(-2), "overview line " .. index .. " preserves right padding")
  end
  test.highlighted(constrained, "deliberately long", "ProudBright", "wrapped title highlights remain semantic")
  test.highlighted(constrained, "A very long Markdown heading", "ProudAccentText", "wrapped Markdown headings remain highlighted")

  local provider = require("proud.provider")
  local metadata_state = feature.create(provider.normalize_pull_request({
    number = 731,
    title = "Use bounded retry budget",
    body = "## Summary\nAPI summary payload from the pull request body.\n\n## Testing\n- [x] unit\n",
    labels = { nodes = { { name = "api-label" }, { name = "performance" } } },
    requestedReviewers = { nodes = { { login = "pending-reviewer" } } },
    latestReviews = { nodes = {
      {
        author = { login = "changes-reviewer" },
        state = "CHANGES_REQUESTED",
        submittedAt = "2026-10-15T11:00:00Z",
        body = "Cap the retry delay.",
      },
    } },
    comments = {
      {
        user = { login = "comment-author" },
        created_at = "2026-10-15T11:36:00Z",
        body = "The API conversation comment.",
      },
    },
    files = {},
    commits = {},
    statusCheckRollup = {},
  }))
  local metadata_text = table.concat(feature.render(metadata_state).lines, "\n")
  test.contains(metadata_text, "changes-reviewer changes requested", "overview uses API reviewer decisions")
  test.contains(metadata_text, "pending-reviewer review pending", "overview uses requested reviewers from the API")
  test.contains(metadata_text, "api-label · performance", "overview uses the exact API labels")
  test.contains(metadata_text, "API summary payload from the pull request body.", "overview description comes from the API body")
  test.contains(table.concat(metadata_state.conversation_cards[2].lines, "\n"), "The API conversation comment.", "overview conversation comes from API comments")
  test.truthy(not metadata_text:find("dev-lee", 1, true), "overview does not leak fixture reviewers")
  test.truthy(not metadata_text:find("Backoff math is off by one", 1, true), "overview does not leak fixture conversation")

  local review_comment_state = feature.create(provider.normalize_pull_request({
    number = 732,
    title = "Review thread rendering",
    reviews = {
      { id = 301, author = "review-author", state = "changes_requested", body = "" },
    },
    review_comments = {
      {
        id = 401,
        pull_request_review_id = 301,
        user = { login = "inline-reviewer" },
        body = "Please invert this condition.",
      },
    },
    comments = {},
  }))
  local review_comment_view = feature.render(review_comment_state)
  local review_comment_text = {}
  for _, card in ipairs(review_comment_view.conversation_cards or {}) do
    table.insert(review_comment_text, table.concat(card.lines, "\n"))
  end
  test.contains(
    table.concat(review_comment_text, "\n"),
    "Please invert this condition.",
    "review messages render beneath their review even when the review summary is empty"
  )

  local colliding_review_state = feature.create(provider.normalize_pull_request({
    number = 733,
    title = "Review identity",
    reviews = {
      { id = 601, user = { login = "mory91" }, state = "DISMISSED", body = "" },
      { id = 602, user = { login = "mory91" }, state = "APPROVED", body = "" },
    },
    review_comments = {
      {
        id = 601,
        pull_request_review_id = 601,
        user = { login = "inline-reviewer" },
        body = "First inline review message.",
      },
      {
        id = 602,
        pull_request_review_id = 602,
        user = { login = "inline-reviewer" },
        body = "Second inline review message.",
      },
    },
    comments = {},
  }))
  local colliding_review_view = feature.render(colliding_review_state)
  local colliding_review_text = {}
  for _, card in ipairs(colliding_review_view.conversation_cards or {}) do
    table.insert(colliding_review_text, table.concat(card.lines, "\n"))
  end
  test.eq(4, #colliding_review_view.conversation_cards, "reviews and review comments keep separate identities")
  test.contains(table.concat(colliding_review_text, "\n"), "First inline review message.")
  test.contains(table.concat(colliding_review_text, "\n"), "Second inline review message.")

  local placeholder = feature.create({ number = 901, title = "Pull request #901" }, { loading = true })
  local tree = require("proud.components.tree")
  test.truthy(tree.find(placeholder.sidebar, "loading:files"), "loading overview exposes navigable placeholder rows")
  local sidebar_state = placeholder.sidebar
  tree.select(placeholder.sidebar, "commits")
  tree.collapse(placeholder.sidebar)
  test.contains(table.concat(feature.render(placeholder).lines, "\n"), "Loading pull request details...", "placeholder overview renders before provider data")
  feature.hydrate(placeholder, provider.normalize_pull_request({
    number = 901,
    title = "Loaded overview",
    body = "Loaded body",
    commits = { { sha = "feed123", message = "Subject\n\nBody" } },
    files = { { path = "src/loaded.ts", additions = 1, deletions = 0 } },
  }))
  test.truthy(rawequal(sidebar_state, placeholder.sidebar), "hydration preserves the tree-state identity used by keyboard callbacks")
  test.truthy(not placeholder.loading, "hydration clears the overview loading state")
  test.eq("commits", tree.selected(placeholder.sidebar).id, "hydration preserves the reviewer's selected sidebar node")
  test.eq(false, tree.find(placeholder.sidebar, "commits").expanded, "hydration preserves explicit sidebar collapse")
  test.contains(table.concat(feature.render(placeholder).lines, "\n"), "Loaded overview")
  test.contains(table.concat(feature.render(placeholder).lines, "\n"), "Loaded body")
  tree.expand(placeholder.sidebar, "commits")
  test.contains(table.concat(feature.render_panes(placeholder).sidebar.lines, "\n"), "feed123 Subject")
end
