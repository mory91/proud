return function(test)
  local feature = require("proud.loader").load("conversation_cards")
  vim.cmd("vnew")
  local host_window = vim.api.nvim_get_current_win()
  local host_buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(host_buffer, 0, -1, false, vim.fn["repeat"]({ "" }, 40))
  vim.api.nvim_win_set_width(host_window, 70)
  vim.api.nvim_win_set_height(host_window, 20)

  local specs = feature.layout({
    {
      id = "review",
      author = "dev-lee",
      age = "1h",
      meta_segments = {
        { text = "  reviewed", group = "ProudMuted" },
        { text = "  change requested", group = "ProudWarning" },
      },
      body = "Backoff math is off by one in retry.ts.",
    },
    {
      id = "reply",
      depth = 1,
      author = "sara-k",
      age = "40m",
      meta_segments = { { text = "  commented", group = "ProudMuted" } },
      body = "Good catch. Pushing a fix in the next commit.",
    },
  }, {
    width = 68,
    margin = 0,
    start_row = 5,
    gap = 1,
  })
  test.eq(2, #specs)
  test.eq(5, specs[1].row)
  test.truthy(specs[2].row > specs[1].row, "reply card is below its parent")
  test.truthy(specs[2].col > specs[1].col, "reply card is indented")
  test.truthy(specs[2].width < specs[1].width, "reply card is narrower than its parent")
  test.contains(specs[1].lines[1], "dev-lee  reviewed  change requested  · 1h ago")
  test.contains(specs[2].lines[1], "sara-k  commented  · 40m ago")
  local offset_specs = feature.layout({
    { id = "offset-root", author = "offset-reviewer", age = "1h", body = "Offset root" },
    { id = "offset-reply", depth = 1, author = "offset-author", age = "20m", body = "Offset reply" },
  }, {
    width = 60,
    margin = 0,
    start_row = 1,
    col_offset = 3,
    min_width = 12,
  })
  test.eq(3, offset_specs[1].col, "card layout honors the left content offset")
  test.eq(5, offset_specs[2].col, "reply offset is relative to the content offset")

  local state = feature.create({ host_window = host_window })
  test.eq(2, feature.sync(state, specs), "both cards fit in the host viewport")
  local review_card = state.cards.review
  local reply_card = state.cards.reply
  test.truthy(vim.api.nvim_win_is_valid(review_card.window))
  test.truthy(vim.api.nvim_win_is_valid(reply_card.window))
  local review_config = vim.api.nvim_win_get_config(review_card.window)
  local reply_config = vim.api.nvim_win_get_config(reply_card.window)
  test.eq("win", review_config.relative)
  test.eq("rounded", type(review_config.border) == "table" and "rounded" or review_config.border)
  test.eq("╭", review_config.border[1])
  test.eq("╮", review_config.border[3])
  test.eq(host_window, review_config.win)
  test.truthy(reply_config.width < review_config.width)
  test.contains(vim.wo[review_card.window].winhighlight, "Normal:ProudCard", "root cards use the overview background")
  test.contains(vim.wo[reply_card.window].winhighlight, "Normal:ProudCardReply", "replies use the subtle panel shade")
  local review_text = table.concat(vim.api.nvim_buf_get_lines(review_card.buffer, 0, -1, false), "\n")
  test.truthy(not review_text:find("╭", 1, true), "card content has no text-drawn top border")
  test.truthy(not review_text:find("│", 1, true), "card content has no text-drawn side border")
  test.contains(review_text, "change requested")

  local namespace = vim.api.nvim_get_namespaces().proud_conversation_cards
  local marks = vim.api.nvim_buf_get_extmarks(review_card.buffer, namespace, 0, -1, { details = true })
  local groups = {}
  for _, mark in ipairs(marks) do
    groups[mark[4].hl_group] = true
  end
  test.truthy(groups.ProudAccentText, "author metadata is accented")
  test.truthy(groups.ProudWarning, "change-requested metadata uses warning color")
  test.truthy(groups.ProudMuted, "relative age metadata is muted")
  local theme = require("proud.theme").groups()
  test.eq(theme.ProudBackground.bg, theme.ProudCard.bg, "root card background matches the overview")
  test.eq(theme.ProudPanel.bg, theme.ProudCardReply.bg, "reply background uses the simple panel shade")
  test.truthy(theme.ProudCardReply.bg ~= theme.ProudCard.bg, "replies are visually elevated from root cards")

  vim.api.nvim_win_call(host_window, function()
    vim.fn.winrestview({ topline = 3, lnum = 3 })
  end)
  feature.sync(state, specs)
  test.eq(2, vim.api.nvim_win_get_config(review_card.window).row, "cards follow host buffer scrolling")

  local top_body = {}
  for index = 1, 10 do
    table.insert(top_body, ("Top clipped body line %d."):format(index))
  end
  local top_specs = feature.layout({
    {
      id = "top-clip",
      author = "top-reviewer",
      age = "2h",
      body = table.concat(top_body, "\n"),
    },
  }, {
    width = 68,
    margin = 0,
    start_row = 4,
  })
  vim.api.nvim_win_call(host_window, function()
    vim.fn.winrestview({ topline = top_specs[1].row + 2, lnum = top_specs[1].row })
  end)
  feature.sync(state, top_specs)
  local top_card = state.cards["top-clip"]
  test.truthy(top_card ~= nil, "a top-clipped card stays mounted")
  local top_config = vim.api.nvim_win_get_config(top_card.window)
  test.eq(0, top_config.row, "top-clipped content starts at the host viewport")
  test.eq(top_specs[1].height - 1, top_config.height, "the clipped header is removed from the card buffer")
  test.eq("", top_config.border[1], "the offscreen top edge is omitted")
  test.eq("", top_config.border[3], "the offscreen top-right edge is omitted")
  test.eq("╯", top_config.border[5], "the visible bottom edge remains rounded")
  local top_text = table.concat(vim.api.nvim_buf_get_lines(top_card.buffer, 0, -1, false), "\n")
  test.truthy(not top_text:find("top-reviewer", 1, true), "the clipped header is not rendered")
  test.contains(top_text, "Top clipped body line 1.", "visible body rows remain rendered")

  local bottom_body = {}
  for index = 1, 12 do
    table.insert(bottom_body, ("Bottom clipped body line %d."):format(index))
  end
  local bottom_specs = feature.layout({
    {
      id = "bottom-clip",
      author = "bottom-reviewer",
      age = "3h",
      body = table.concat(bottom_body, "\n"),
    },
  }, {
    width = 68,
    margin = 0,
    start_row = 15,
  })
  vim.api.nvim_win_call(host_window, function()
    vim.fn.winrestview({ topline = 1, lnum = bottom_specs[1].row })
  end)
  feature.sync(state, bottom_specs)
  local bottom_card = state.cards["bottom-clip"]
  test.truthy(bottom_card ~= nil, "a bottom-clipped card stays mounted")
  local bottom_config = vim.api.nvim_win_get_config(bottom_card.window)
  test.eq(bottom_specs[1].row - 1, bottom_config.row, "the visible top edge stays aligned")
  test.truthy(bottom_config.height < bottom_specs[1].height, "only visible body rows are rendered")
  test.eq("╭", bottom_config.border[1], "the visible top edge remains rounded")
  test.eq("", bottom_config.border[5], "the offscreen bottom-right edge is omitted")
  test.eq("", bottom_config.border[7], "the offscreen bottom-left edge is omitted")
  local bottom_text = table.concat(vim.api.nvim_buf_get_lines(bottom_card.buffer, 0, -1, false), "\n")
  test.contains(bottom_text, "bottom-reviewer", "the visible header remains rendered")
  test.truthy(not bottom_text:find("Bottom clipped body line 12.", 1, true), "offscreen body rows are not rendered")

  vim.api.nvim_win_call(host_window, function()
    vim.fn.winrestview({
      topline = bottom_specs[1].row + bottom_specs[1].height + 4,
      lnum = bottom_specs[1].row,
    })
  end)
  feature.sync(state, bottom_specs)
  test.truthy(state.cards["bottom-clip"] == nil, "a card closes only after it completely exits the viewport")

  local narrow = feature.layout({
    { id = "review", author = "dev-lee", age = "1h", body = "Resize me" },
  }, { width = 38, margin = 0, start_row = 5 })
  vim.api.nvim_win_call(host_window, function()
    vim.fn.winrestview({ topline = 1, lnum = 5 })
  end)
  feature.sync(state, narrow)
  test.eq(1, vim.tbl_count(state.cards), "replaced layouts release removed card windows")
  test.eq(38, vim.api.nvim_win_get_config(state.cards.review.window).width)

  local review_buffer = state.cards.review.buffer
  feature.close(state)
  test.truthy(not vim.api.nvim_buf_is_valid(review_buffer), "close wipes native card buffers")
  vim.cmd("silent! bwipeout!")
end
