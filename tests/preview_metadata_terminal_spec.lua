local provider = require("proud.provider")
local session = require("proud.session")

local raw_pull = {
  number = 731,
  title = "Use bounded retry budget",
  user = { login = "api-author" },
  state = "open",
  body = (function()
    local lines = { "API description first message from the pull request body.", "" }
    for index = 2, 29 do
      table.insert(lines, ("API description line %d for real-terminal scrolling."):format(index))
    end
    table.insert(lines, "Final description line for complete rendering.")
    return table.concat(lines, "\n")
  end)(),
  labels = { nodes = { { name = "api-label-one" }, { name = "api-label-two" } } },
  requestedReviewers = { nodes = { { login = "pending-api-reviewer" } } },
  latestReviews = { nodes = {
    {
      id = 301,
      author = { login = "changes-api-reviewer" },
      state = "CHANGES_REQUESTED",
      submittedAt = "2026-10-15T11:00:00Z",
      body = "",
    },
  } },
  comments = {
    {
      id = 401,
      user = { login = "api-comment-author" },
      created_at = "2026-10-15T11:36:00Z",
      body = "API conversation comment payload.",
    },
    {
      id = 402,
      in_reply_to_id = 401,
      user = { login = "api-reply-author" },
      created_at = "2026-10-15T11:40:00Z",
      body = "API conversation reply payload.",
    },
  },
  review_comments = {
    {
      id = 403,
      pull_request_review_id = 301,
      user = { login = "api-inline-reviewer" },
      created_at = "2026-10-15T11:30:00Z",
      body = "API inline review message.",
    },
  },
  additions = 77,
  deletions = 9,
  reviewThreads = { totalCount = 2 },
  head = { ref = "feat/api-metadata", sha = "head-sha" },
  base = { ref = "main" },
  files = {
    { filename = "src/retry.ts", status = "MODIFIED", additions = 77, deletions = 9 },
  },
  commits = {
    { sha = "abc1234", commit = { message = "Use bounded retry budget" } },
  },
  statusCheckRollup = {
    { name = "unit", conclusion = "SUCCESS" },
  },
}

local function visible_text()
  local state = session.current and session.current.state
  local workspace = state and (state.workspace or state.surface)
  local lines = {}
  for _, pane in pairs(workspace and workspace.panes or {}) do
    if pane.buffer and vim.api.nvim_buf_is_valid(pane.buffer) then
      vim.list_extend(lines, vim.api.nvim_buf_get_lines(pane.buffer, 0, -1, false))
    end
  end
  for _, card in pairs(state and state.comment_card_windows and state.comment_card_windows.cards or {}) do
    if card.buffer and vim.api.nvim_buf_is_valid(card.buffer) then
      vim.list_extend(lines, vim.api.nvim_buf_get_lines(card.buffer, 0, -1, false))
    end
  end
  return table.concat(lines, "\n")
end

local function assert_metadata(expect_comment)
  local text = visible_text()
  local normalized_text = text:gsub("%s+", " ")
  local required = {
    "changes-api-reviewer changes requested",
    "pending-api-reviewer review pending",
    "api-label-one · api-label-two",
    "API description first message from the pull request body.",
    "Final description line for complete rendering.",
  }
  if expect_comment then
    table.insert(required, "API conversation comment payload.")
    table.insert(required, "api-comment-author  commented")
    table.insert(required, "API conversation reply payload.")
    table.insert(required, "api-reply-author  commented")
    table.insert(required, "API inline review message.")
  end
  for _, value in ipairs(required) do
    local normalized_value = value:gsub("%s+", " ")
    assert(normalized_text:find(normalized_value, 1, true), "missing terminal metadata: " .. value)
  end
  for _, value in ipairs({ "## Summary", "dev-lee", "Exponential retry", "Backoff math is off by one" }) do
    local normalized_value = value:gsub("%s+", " ")
    assert(not normalized_text:find(normalized_value, 1, true), "fixture metadata leaked into terminal: " .. value)
  end
end

local browser = require("proud.loader").load("pull_request_browser")
local browser_state = browser.create({ provider.normalize_pull_request(raw_pull) }, { query = "" })
local browser_buffer = browser.open(browser_state, { mode = "surface" })
session.current = { feature = "pull_request_browser", state = browser_state, buffer = browser_buffer }
assert_metadata(false)
vim.api.nvim_echo({ { "PREVIEW_METADATA_TERMINAL_READY=true" } }, false, {})

function ProudMetadataOpenOverview()
  vim.cmd("silent! tabclose!")
  local overview = require("proud.loader").load("pull_request_overview")
  local overview_state = overview.create(provider.normalize_pull_request(raw_pull))
  local overview_buffer = overview.open(overview_state)
  session.current = { feature = "pull_request_overview", state = overview_state, buffer = overview_buffer }
  local first_card = overview_state.comment_card_windows.specs[1]
  vim.api.nvim_win_call(overview_state.workspace.panes.details.window, function()
    vim.fn.winrestview({ topline = math.max(1, first_card.row - 2), lnum = first_card.row })
  end)
  require("proud.loader").load("conversation_cards").sync(
    overview_state.comment_card_windows,
    overview_state.comment_card_windows.specs
  )
  assert_metadata(true)
  vim.api.nvim_echo({ { "OVERVIEW_METADATA_TERMINAL_READY=true" } }, false, {})
end

function ProudMetadataAssertPreviewScrolled()
  local preview_window = session.current.state.surface.panes.preview.window
  local view = vim.api.nvim_win_call(preview_window, function()
    return vim.fn.winsaveview()
  end)
  assert(view.topline > 1, "description did not scroll down")
  vim.api.nvim_echo({ { "PREVIEW_DESCRIPTION_SCROLL_OK=true" } }, false, {})
end

function ProudMetadataAssertPreviewAtTop()
  local preview_window = session.current.state.surface.panes.preview.window
  local view = vim.api.nvim_win_call(preview_window, function()
    return vim.fn.winsaveview()
  end)
  assert(view.topline == 1, "description did not scroll back to the first message")
  vim.api.nvim_echo({ { "PREVIEW_DESCRIPTION_TOP_OK=true" } }, false, {})
end

function ProudMetadataAssertOverviewPadding()
  local state = assert(session.current and session.current.state, "overview state is missing")
  local details = assert(state.workspace and state.workspace.panes.details, "overview details pane is missing")
  local width = vim.api.nvim_win_get_width(details.window)
  local lines = vim.api.nvim_buf_get_lines(details.buffer, 0, -1, false)
  assert(lines[1] and lines[1]:sub(1, 2) == "  ", "overview content misses left padding")
  assert(lines[1] and lines[1]:sub(-2) == "  ", "overview content misses right padding")
  local cards = assert(state.comment_card_windows, "conversation cards are missing")
  local root = assert(cards.cards[cards.specs[1].id], "root conversation card is missing")
  local config = vim.api.nvim_win_get_config(root.window)
  assert(config.col == 2, "root conversation card misses left padding")
  assert(config.col + config.width + 2 <= width - 2, "root conversation card exceeds right padding")
  vim.api.nvim_echo({ { "OVERVIEW_PADDING_OK=true" } }, false, {})
end

function ProudMetadataAssertConversationCardColors()
  local state = assert(session.current and session.current.state, "overview state is missing")
  local cards = assert(state.comment_card_windows, "conversation cards are missing")
  local theme = require("proud.theme").groups()
  assert(theme.ProudCard.bg == theme.ProudBackground.bg, "root cards do not match the overview background")
  assert(theme.ProudCardReply.bg == theme.ProudPanel.bg, "replies do not use the simple panel shade")
  local root = assert(cards.cards[cards.specs[1].id], "root conversation card is missing")
  assert(vim.wo[root.window].winhighlight:find("Normal:ProudCard", 1, true), "root card misses its background mapping")
  if cards.specs[2] and cards.cards[cards.specs[2].id] then
    local reply = cards.cards[cards.specs[2].id]
    assert(vim.wo[reply.window].winhighlight:find("Normal:ProudCardReply", 1, true), "reply card misses its shade mapping")
  end
  vim.api.nvim_echo({ { "CONVERSATION_CARD_COLORS_OK=true" } }, false, {})
end

function ProudMetadataAssertConversationCardClipping()
  local state = assert(session.current and session.current.state, "overview state is missing")
  local cards = assert(state.comment_card_windows, "conversation cards are missing")
  local spec = assert(cards.specs[1], "conversation card layout is missing")
  vim.api.nvim_win_call(state.workspace.panes.details.window, function()
    vim.fn.winrestview({ topline = spec.row + 2, lnum = spec.row })
  end)
  require("proud.loader").load("conversation_cards").sync(cards, cards.specs)
  local card = assert(cards.cards[spec.id], "partially visible card was destroyed")
  local config = vim.api.nvim_win_get_config(card.window)
  assert(card.visible.top_visible == false, "card top edge should be clipped")
  assert(config.border[1] == "", "offscreen top border should be omitted")
  local text = table.concat(vim.api.nvim_buf_get_lines(card.buffer, 0, -1, false), "\n")
  local first_visible = assert(spec.lines[card.visible.first_line], "clipped body row is missing")
  assert(card.visible.first_line > 1, "clipped card header should not render")
  assert(config.height < spec.height, "clipped card should render only visible rows")
  assert(text:find(vim.trim(first_visible), 1, true), "visible card body should remain")
  vim.api.nvim_echo({ { "CONVERSATION_CARD_CLIP_OK=true" } }, false, {})
end

function ProudMetadataAssertConversationCardExited()
  local state = assert(session.current and session.current.state, "overview state is missing")
  local cards = assert(state.comment_card_windows, "conversation cards are missing")
  local spec = assert(cards.specs[1], "conversation card layout is missing")
  vim.api.nvim_win_call(state.workspace.panes.details.window, function()
    vim.fn.winrestview({
      topline = spec.row + spec.height + 4,
      lnum = spec.row,
    })
  end)
  require("proud.loader").load("conversation_cards").sync(cards, cards.specs)
  assert(cards.cards[spec.id] == nil, "fully exited card should be destroyed")
  vim.api.nvim_echo({ { "CONVERSATION_CARD_EXIT_OK=true" } }, false, {})
end
