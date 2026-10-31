return function(test)
  local overview = require("proud.loader").load("pull_request_overview")
  local fixtures = require("proud.fixtures")
  local state = overview.create(fixtures.overview)
  overview.open(state)
  local cards = state.comment_card_windows
  test.truthy(cards ~= nil, "overview mounts native conversation card windows")
  local first_spec = cards.specs[1]
  vim.api.nvim_win_call(state.workspace.panes.details.window, function()
    vim.fn.winrestview({ topline = math.max(1, first_spec.row - 2), lnum = first_spec.row })
  end)
  local conversation_cards = require("proud.loader").load("conversation_cards")
  conversation_cards.sync(cards, cards.specs)
  test.eq(2, vim.tbl_count(cards.cards), "overview opens one native card per conversation entry")
  for _, card in pairs(cards.cards) do
    local config = vim.api.nvim_win_get_config(card.window)
    test.eq("╭", config.border[1], "conversation cards use Neovim's native rounded border")
    test.eq(false, config.focusable, "display cards do not steal overview focus")
    local text = table.concat(vim.api.nvim_buf_get_lines(card.buffer, 0, -1, false), "\n")
    test.truthy(not text:find("╭", 1, true), "native cards do not print border glyphs")
    test.truthy(not text:find("│", 1, true), "native cards do not print separator glyphs")
  end

  vim.api.nvim_win_call(state.workspace.panes.details.window, function()
    vim.fn.winrestview({ topline = first_spec.row + 2, lnum = first_spec.row })
  end)
  conversation_cards.sync(cards, cards.specs)
  local clipped = cards.cards[first_spec.id]
  test.truthy(clipped ~= nil, "a partially visible conversation card remains mounted")
  test.truthy(clipped.visible.top_visible == false, "the clipped top edge is marked invisible")
  test.eq("", vim.api.nvim_win_get_config(clipped.window).border[1], "the offscreen rounded top edge is omitted")
  local clipped_text = table.concat(vim.api.nvim_buf_get_lines(clipped.buffer, 0, -1, false), "\n")
  test.contains(clipped_text, "Backoff math is off by one", "the visible card body remains available")

  vim.api.nvim_win_call(state.workspace.panes.details.window, function()
    vim.fn.winrestview({
      topline = first_spec.row + first_spec.height + 4,
      lnum = first_spec.row,
    })
  end)
  conversation_cards.sync(cards, cards.specs)
  test.truthy(cards.cards[first_spec.id] == nil, "a card closes after it completely leaves the viewport")

  local workspace = state.workspace
  vim.cmd("silent! tabclose!")
  test.truthy(not vim.api.nvim_tabpage_is_valid(workspace.tabpage), "scene close removes the card host")
end
