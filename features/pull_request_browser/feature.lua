local ui = require("proud.ui")
local keymap = require("proud.keymap")
local debounce = require("proud.debounce")

local M = {}

local decision_labels = {
  CHANGES_REQUESTED = "changes requested",
  REVIEW_REQUIRED = "Review request",
  APPROVED = "approved",
  COMMENTED = "commented",
  DRAFT = "draft",
}

local decision_highlights = {
  CHANGES_REQUESTED = "ProudWarning",
  REVIEW_REQUIRED = "ProudAccentText",
  APPROVED = "ProudSuccessText",
  COMMENTED = "ProudMuted",
  DRAFT = "ProudMuted",
}

local compact_decision_labels = {
  CHANGES_REQUESTED = "changes",
  REVIEW_REQUIRED = "review",
  APPROVED = "approved",
  COMMENTED = "commented",
  DRAFT = "draft",
}

local reviewer_state_labels = {
  approved = "approved",
  changes_requested = "changes requested",
  commented = "commented",
  dismissed = "dismissed",
  pending = "review pending",
}

local reviewer_state_highlights = {
  approved = "ProudSuccessText",
  changes_requested = "ProudWarning",
  commented = "ProudMuted",
  dismissed = "ProudMuted",
  pending = "ProudAccentText",
}

local cursor_rail = "▌"
local subtitle_separator = " · "
local compact_subtitle_separator = "·"
local sources = {
  { id = "review_requested", label = "Review requested", query = "is:open review-requested:@me" },
  { id = "mine", label = "Mine", query = "is:open author:@me" },
  { id = "all_open", label = "All open", query = "is:open" },
  { id = "recently_viewed", label = "Recently viewed", query = "is:open interacted-by:@me sort:updated-desc" },
  { id = "branches", label = "Branches", query = "is:open base:main sort:updated-desc" },
}

local function safe_text(value, fallback)
  if type(value) == "string" or type(value) == "number" then
    return tostring(value)
  end
  return fallback
end

local function safe_number(value, fallback)
  return tonumber(value) or fallback
end

function M.sources()
  return vim.deepcopy(sources)
end

local function pull_author(pull)
  if type(pull.author) == "table" then
    return safe_text(pull.author.login or pull.author.name, "unknown")
  end
  return safe_text(pull.author, "unknown")
end

local function labels(pull)
  local values = {}
  for _, label in ipairs(pull.labels or {}) do
    local value = type(label) == "table" and label.name or label
    value = safe_text(value, "")
    if value ~= "" then
      table.insert(values, value)
    end
  end
  return values
end

local function body_lines(value)
  if type(value) == "table" then
    local lines = {}
    for _, line in ipairs(value) do
      table.insert(lines, safe_text(line, ""))
    end
    return lines
  end
  local text = safe_text(value, "")
  return text == "" and {} or vim.split(text, "\n", { plain = true })
end

local function reviewers(pull)
  local values = {}
  local seen = {}
  local function add(value, fallback_state)
    if type(value) ~= "table" then
      return
    end
    local requested = type(value.requestedReviewer) == "table" and value.requestedReviewer or nil
    local login = safe_text(value.login or value.name or (requested and (requested.login or requested.name)), "")
    if login == "" or seen[login] then
      return
    end
    local raw_state = safe_text(value.state or fallback_state or "pending", "pending")
    local state = raw_state:lower():gsub("[%s%-]", "_")
    if state == "" or state == "review_required" or state == "requested" then
      state = "pending"
    end
    seen[login] = true
    table.insert(values, { login = login, state = state })
  end
  for _, reviewer in ipairs(pull.reviewers or {}) do
    add(reviewer, "pending")
  end
  if #values == 0 then
    for _, reviewer in ipairs(pull.requested_reviewers or {}) do
      add(reviewer, "pending")
    end
    local requests = pull.reviewRequests or pull.requestedReviewers
    for _, reviewer in ipairs(type(requests) == "table" and (requests.nodes or requests) or {}) do
      add(reviewer, "pending")
    end
    local reviews = pull.reviews or pull.latestReviews
    for _, review in ipairs(type(reviews) == "table" and (reviews.nodes or reviews) or {}) do
      add(review, "commented")
    end
  end
  return values
end

local function status_highlight(pull)
  if pull.is_draft then
    return "ProudMuted"
  end
  local state = safe_text(pull.state, "Open"):lower()
  if state == "merged" then
    return "ProudAccentText"
  end
  if state == "closed" then
    return "ProudDangerText"
  end
  return "ProudSuccessText"
end

local function matches(pull, query)
  query = query:lower()
  local author = pull_author(pull):lower()
  local title = (pull.title or ""):lower()
  local pull_labels = {}
  for _, label in ipairs(labels(pull)) do
    pull_labels[label:lower()] = true
  end
  for token in query:gmatch("%S+") do
    local key, value = token:match("^(%a+):(.+)$")
    if key == "is" then
      if value == "draft" and not pull.is_draft then
        return false
      end
      if value == "open" and pull.is_draft then
        return false
      end
    elseif key == "author" and author ~= value then
      return false
    elseif key == "label" and not pull_labels[value] then
      return false
    elseif not key and not title:find(token, 1, true) and not author:find(token, 1, true) and tostring(pull.number) ~= token then
      return false
    end
  end
  return true
end

function M.create(pulls, options)
  options = options or {}
  pulls = pulls or {}
  local source_index = math.max(1, math.min(#sources, safe_number(options.source_index, 3)))
  for _, pull in ipairs(pulls) do
    if pull.body ~= nil then
      pull.description_loaded = true
    end
  end
  local state = {
    pulls = pulls,
    total_count = safe_number(options.total_count, #pulls),
    query = options.query or "is:open",
    display_query = options.display_query or options.query or "is:open",
    source = options.source or sources[source_index].id,
    source_index = source_index,
    cursor = 1,
    page_size = 0,
    prefetch_pages = safe_number(options.prefetch_pages, 2),
    has_next_page = false,
    next_cursor = nil,
    description_loading = {},
  }
  M.filter(state)
  return state
end

function M.page_size_for_height(height)
  local rows = math.max(1, math.floor(tonumber(height) or 1))
  return math.max(1, math.floor((rows - 2) / 2))
end

function M.apply_page(state, page, options)
  options = options or {}
  page = type(page) == "table" and page or {}
  local pulls = type(page.pulls) == "table" and page.pulls or type(page[1]) == "table" and page or {}
  if options.replace then
    state.pulls = {}
    state.cursor = 1
    state.next_cursor = nil
    state.has_next_page = false
  end
  local seen = {}
  for _, pull in ipairs(state.pulls) do
    seen[safe_number(pull.number, 0)] = true
  end
  for _, pull in ipairs(pulls) do
    local number = safe_number(pull.number, 0)
    if number ~= 0 and not seen[number] then
      if pull.body ~= nil then
        pull.description_loaded = true
      end
      table.insert(state.pulls, pull)
      seen[number] = true
    end
  end
  state.total_count = math.max(safe_number(page.total_count, state.total_count or 0), #state.pulls)
  state.next_cursor = page.next_cursor
  state.has_next_page = page.has_next_page == true or (page.next_cursor ~= nil and page.next_cursor ~= "")
  M.filter(state)
end

function M.filter(state)
  state.filtered = {}
  for _, pull in ipairs(state.pulls) do
    if matches(pull, state.query) then
      table.insert(state.filtered, pull)
    end
  end
  state.cursor = math.min(math.max(state.cursor or 1, 1), math.max(#state.filtered, 1))
end

function M.set_query(state, query)
  state.query = query
  state.display_query = query
  state.cursor = 1
  state.cursor_moved = false
  M.filter(state)
end

function M.set_source(state, index)
  index = math.max(1, math.min(#sources, safe_number(index, 3)))
  state.source_index = index
  state.source = sources[index].id
  state.query = sources[index].query
  state.display_query = sources[index].query
  state.cursor = 1
  state.cursor_moved = false
  M.filter(state)
end

function M.move(state, delta)
  if delta ~= 0 and #(state.filtered or {}) > 0 then
    state.cursor_moved = true
  end
  state.cursor = math.max(1, math.min(math.max(#state.filtered, 1), state.cursor + delta))
end

function M.selected(state)
  return state.filtered[state.cursor]
end

function M.counts(state)
  return {
    filtered = #(state.filtered or {}),
    total = math.max(safe_number(state.total_count, #(state.pulls or {})), #(state.filtered or {})),
  }
end

function M.count_label(state)
  local counts = M.counts(state)
  return counts.filtered .. "/" .. counts.total
end

local function count_segments(state)
  local counts = M.counts(state)
  return {
    { text = tostring(counts.filtered), group = "ProudAccentText" },
    { text = "/", group = "ProudBorder" },
    { text = tostring(counts.total), group = "ProudMuted" },
  }
end

local fit = ui.fit
local display_width = ui.display_width

local function layout_widths(width)
  local terminal_width = math.max(40, math.floor(width or vim.o.columns or 160))
  local left_width = math.max(24, math.min(70, math.floor(terminal_width * 0.44)))
  return left_width, math.max(10, terminal_width - left_width - 2)
end

local function push_flat(highlights, row, start_col, end_col, group)
  table.insert(highlights, row)
  table.insert(highlights, start_col)
  table.insert(highlights, end_col)
  table.insert(highlights, group)
end

local function add_title_row(lines, highlights, pull, width, selected)
  local prefix = selected and cursor_rail or " "
  local number = "#" .. safe_text(pull.number, "0")
  local title = safe_text(pull.title, "Untitled pull request")
  local line = fit(prefix .. "● " .. number .. " " .. title, width)
  local row = #lines
  table.insert(lines, line)
  if selected then
    push_flat(highlights, row, 0, #line, "ProudSelection")
    push_flat(highlights, row, 0, math.min(#prefix, #line), "ProudAccentText")
  end
  local circle_start = #prefix
  local number_start = circle_start + #"● "
  local title_start = number_start + #number + 1
  push_flat(highlights, row, circle_start, math.min(circle_start + #"●", #line), status_highlight(pull))
  push_flat(highlights, row, number_start, math.min(number_start + #number, #line), "ProudAccentText")
  push_flat(highlights, row, title_start, math.min(title_start + #title, #line), "ProudBright")
end

local function add_subtitle_row(lines, highlights, pull, width, selected)
  local author = pull_author(pull)
  local age = safe_text(pull.age, "now")
  local additions = math.max(0, math.floor(safe_number(pull.additions, 0)))
  local deletions = math.max(0, math.floor(safe_number(pull.deletions, 0)))
  local addition_label = "+" .. additions
  local deletion_label = "-" .. deletions
  local threads = math.max(0, math.floor(safe_number(pull.threads, 0)))
  local thread_label = threads == 0 and "no threads" or threads == 1 and "1 thread" or threads .. " threads"
  local decision = safe_text(pull.review_decision, "")
  local compact = width < 48
  local decision_label = compact and (compact_decision_labels[decision] or "open")
    or (decision_labels[decision] or "open")
  local separator = width < 36 and compact_subtitle_separator or subtitle_separator
  local fixed_width = display_width(age)
    + display_width(separator) * 4
    + display_width(addition_label)
    + display_width(deletion_label)
    + display_width(thread_label)
    + display_width(decision_label)
  local author_width = math.max(1, width - 1 - fixed_width)
  if display_width(author) > author_width then
    author = fit(author, author_width):gsub("%s+$", "")
  end
  local prefix = selected and cursor_rail or " "
  local line = fit(
    prefix
      .. author
      .. separator
      .. age
      .. separator
      .. addition_label
      .. deletion_label
      .. separator
      .. thread_label
      .. separator
      .. decision_label,
    width
  )
  local row = #lines
  table.insert(lines, line)
  if selected then
    push_flat(highlights, row, 0, #line, "ProudSelection")
    push_flat(highlights, row, 0, math.min(#prefix, #line), "ProudAccentText")
  end
  local offset = #prefix
  push_flat(highlights, row, offset, math.min(offset + #author, #line), "ProudMuted")
  offset = offset + #author + #separator
  push_flat(highlights, row, offset, math.min(offset + #age, #line), "ProudMuted")
  offset = offset + #age + #separator
  push_flat(highlights, row, offset, math.min(offset + #addition_label, #line), "ProudSuccessText")
  offset = offset + #addition_label
  push_flat(highlights, row, offset, math.min(offset + #deletion_label, #line), "ProudDangerText")
  offset = offset + #deletion_label + #separator
  push_flat(highlights, row, offset, math.min(offset + #thread_label, #line), "ProudWarning")
  offset = offset + #thread_label + #separator
  push_flat(highlights, row, offset, math.min(offset + #decision_label, #line), decision_highlights[decision] or "ProudAccentText")
end

function M.render_list(state, options)
  options = options or {}
  local width = math.max(10, math.floor(options.width or layout_widths(vim.o.columns)))
  local lines = {}
  local highlights = {}
  local function add(value)
    table.insert(lines, fit(value, width))
  end
  for row = 1, math.max(16, #state.filtered * 2) do
    local pull_index = math.ceil(row / 2)
    local pull = state.filtered[pull_index]
    local left = ""
    if pull then
      local item_row = (row - 1) % 2 + 1
      if item_row == 1 then
        add_title_row(lines, highlights, pull, width, pull_index == state.cursor)
      else
        add_subtitle_row(lines, highlights, pull, width, pull_index == state.cursor)
      end
    else
      add(fit(left, width))
    end
  end

  add("")
  add("Select a pull request to open its review overview.")
  add("Visible " .. #state.filtered .. "  ·  Source " .. state.source)
  ui.view.span(lines, highlights, #lines - 2, "Select a pull request", "ProudAccentText", "flat")
  ui.view.span(lines, highlights, #lines - 2, "review overview", "ProudSuccessText", "flat")
  ui.view.span(lines, highlights, #lines - 1, "Visible", "ProudMuted", "flat")
  ui.view.span(lines, highlights, #lines - 1, "Source", "ProudMuted", "flat")
  return { lines = lines, highlights = highlights, highlight_format = "flat" }
end

function M.render_preview(state, options)
  options = options or {}
  local width = math.max(10, math.floor(options.width or select(2, layout_widths(vim.o.columns))))
  local selected = M.selected(state)
  local v = ui.view.new({ width = width })
  if not selected then
    v:line({ "No pull request selected", "ProudMuted" })
    return v:build()
  end
  local state_label = safe_text(selected.state, selected.is_draft and "Draft" or "Open")
  v:line(
    { "#" .. safe_text(selected.number, "0"), "ProudAccentText" }, " ",
    { safe_text(selected.title, "Untitled pull request"), "ProudBright" }
  )
  v:line(
    { "● " .. state_label, status_highlight(selected) }, "    ",
    { pull_author(selected), "ProudAccentText" }, " wants to merge"
  )
  v:line(
    "  ", { safe_text(selected.head_ref, ""), "ProudAccentText" },
    " into ", { safe_text(selected.base_ref, "main"), "ProudAccentText" }
  )
  v:line(
    "  ", { "+" .. tostring(safe_number(selected.additions, 0)), "ProudSuccessText" },
    "  ", { "-" .. tostring(safe_number(selected.deletions, 0)), "ProudDangerText" },
    "  · ", { "◆" .. tostring(safe_number(selected.threads, 0)), "ProudWarning" },
    "  · ", { safe_text(selected.age, "now"), "ProudMuted" }
  )
  local reviewer_values = reviewers(selected)
  if #reviewer_values == 0 then
    v:line({ "Reviewers", "ProudMuted" }, "  none")
  else
    for index, reviewer in ipairs(reviewer_values) do
      local label = reviewer_state_labels[reviewer.state] or reviewer.state
      v:line(
        index == 1 and { "Reviewers", "ProudMuted" } or "         ", "  ",
        { reviewer.login, "ProudAccentText" }, " ",
        { label, reviewer_state_highlights[reviewer.state] or "ProudAccentText" }
      )
    end
  end
  local label_values = labels(selected)
  v:line(
    { "Labels", "ProudMuted" }, "     ",
    { #label_values > 0 and table.concat(label_values, " · ") or "none", "ProudAccentText" }
  )
  v:blank()
  local description = body_lines(selected.body)
  if not selected.description_loaded then
    description = {
      selected.description_error and "Could not load description." or "Loading description...",
    }
  elseif #description == 0 then
    description = { "No description provided." }
  end
  for _, line in ipairs(description) do
    if line:match("^#+%s+") then
      v:line({ line, "ProudAccentText" })
    elseif line:match("^%- %[x%]") then
      v:line({ "- [x]", "ProudSuccessText" }, line:sub(6))
    elseif line:match("^%- %[ %]") then
      v:line({ "- [ ]", "ProudWarning" }, line:sub(6))
    else
      v:line(line)
    end
  end
  return v:build()
end

function M.attach(buffer, state, options)
  options = options or {}
  local query_generation = 0
  local load_page
  local ensure_description
  local ensure_next_page
  local query_debouncer = debounce.new(options.query_debounce_ms or 250, function(query, generation)
    if generation ~= query_generation then
      return
    end
    state.query_pending = true
    if options.on_page then
      load_page({ query = query, replace = true, generation = generation })
      return
    end
    if not options.on_query then
      state.query_pending = false
      return
    end
    options.on_query(query, function(ok, result)
      if generation ~= query_generation then
        return
      end
      state.query_pending = false
      if not ok then
        state.query_error = result and result.message or "Could not refresh pull requests"
      else
        state.query_error = nil
        M.apply_page(state, { pulls = result, total_count = #result }, { replace = true })
        state.cursor = 1
      end
      if state.refresh then
        state.refresh()
      end
    end)
  end)
  state.query_debouncer = query_debouncer
  local request_description
  local description_debouncer = debounce.new(options.description_debounce_ms or 80, function()
    request_description()
  end)
  state.description_debouncer = description_debouncer
  local function dispose_debouncers()
    query_debouncer:dispose()
    description_debouncer:dispose()
  end
  state.dispose_debouncers = dispose_debouncers
  local function cursor_column()
    if state.window and vim.api.nvim_win_is_valid(state.window) then
      return vim.api.nvim_win_get_cursor(state.window)[2]
    end
    return 0
  end
  request_description = function()
    local selected = M.selected(state)
    if not selected or not options.on_description or selected.description_loaded then
      return
    end
    local number = safe_number(selected.number, 0)
    if number == 0 then
      return
    end
    if state.description_loading[number] then
      return
    end
    state.description_loading[number] = true
    options.on_description(number, function(ok, body)
      state.description_loading[number] = nil
      if not ok then
        selected.description_error = body and body.message or "Could not load description"
      else
        selected.description_error = nil
        body = type(body) == "string" and body or ""
        selected.body = body
        selected.description_loaded = true
      end
      local current = M.selected(state)
      if state.refresh and current and safe_number(current.number, 0) == number then
        state.refresh()
      end
    end)
  end
  ensure_description = function()
    local selected = M.selected(state)
    if not selected or not options.on_description or selected.description_loaded then
      description_debouncer:cancel()
      return
    end
    if not state.cursor_moved then
      description_debouncer:cancel()
      request_description()
      return
    end
    description_debouncer:schedule(safe_number(selected.number, 0))
  end
  load_page = function(page_options)
    page_options = page_options or {}
    if not options.on_page then
      return
    end
    if state.loading_page then
      if page_options.replace then
        state.pending_page = page_options
      end
      return
    end
    local generation = page_options.generation or query_generation
    state.loading_page = true
    options.on_page({
      query = page_options.query or state.query,
      limit = state.page_size,
      after = page_options.replace and "" or (page_options.after or state.next_cursor),
    }, function(ok, result)
      if generation ~= query_generation then
        state.loading_page = false
        local pending_page = state.pending_page
        state.pending_page = nil
        if pending_page then
          load_page(pending_page)
        end
        return
      end
      state.loading_page = false
      state.page_loaded = true
      state.query_pending = false
      if not ok then
        state.query_error = result and result.message or "Could not load pull requests"
      else
        state.query_error = nil
        M.apply_page(state, result, { replace = page_options.replace == true })
        if page_options.replace then
          state.cursor = 1
        end
      end
      if state.refresh then
        state.refresh()
      end
    end)
  end
  ensure_next_page = function()
    if not options.on_page
      or state.loading_page
      or not state.has_next_page
      or not state.cursor_moved
      or #state.filtered == 0
    then
      return
    end
    local page_size = math.max(1, safe_number(state.page_size, 1))
    local loaded_pages = math.max(1, math.ceil(#state.pulls / page_size))
    local selected_page = math.max(1, math.ceil(state.cursor / page_size))
    local target_pages = selected_page + math.max(0, safe_number(state.prefetch_pages, 2))
    if loaded_pages < target_pages then
      load_page({ after = state.next_cursor })
    end
  end
  local function refresh(column_override)
    local column = column_override or cursor_column()
    if state.window and vim.api.nvim_win_is_valid(state.window) then
      state.page_size = M.page_size_for_height(vim.api.nvim_win_get_height(state.window))
    end
    if options.surface then
      local list = options.surface.panes.list
      local preview = options.surface.panes.preview
      if not vim.api.nvim_buf_is_valid(list.buffer)
        or not vim.api.nvim_win_is_valid(list.window)
        or not vim.api.nvim_buf_is_valid(preview.buffer)
        or not vim.api.nvim_win_is_valid(preview.window)
      then
        return
      end
      local selected_row = 3 + (state.cursor - 1) * 2
      ui.render(list.buffer, M.render_list(state, { width = vim.api.nvim_win_get_width(list.window) }), { top_pad = 2 })
      ui.render(preview.buffer, M.render_preview(state, { width = vim.api.nvim_win_get_width(preview.window) }), { top_pad = 2 })
      if list.header and list.header.set_trailing then
        list.header.set_trailing(count_segments(state))
      end
      ui.set_cursor(list.buffer, selected_row, column, selected_row + 1, { reserved_rows = 2 })
    else
      if not vim.api.nvim_buf_is_valid(buffer) then
        return
      end
      local selected_row = 3 + (state.cursor - 1) * 2
      ui.render_workspace(options.workspace, {
        list = M.render_list(state),
        preview = M.render_preview(state),
      })
      local preview_window = options.workspace.panes.preview.window
      if vim.api.nvim_win_is_valid(preview_window) then
        vim.api.nvim_win_call(preview_window, function()
          vim.fn.winrestview({ topline = 1, lnum = 1, col = 0, leftcol = 0 })
        end)
      end
      ui.set_cursor(buffer, selected_row, column, selected_row + 1, { reserved_rows = 2 })
    end
    ensure_description()
    ensure_next_page()
  end
  local function preview_window()
    if options.surface and vim.api.nvim_win_is_valid(options.surface.panes.preview.window) then
      return options.surface.panes.preview.window
    end
    if options.workspace and vim.api.nvim_win_is_valid(options.workspace.panes.preview.window) then
      return options.workspace.panes.preview.window
    end
  end
  local function scroll_preview(delta_lines)
    local window = preview_window()
    if not window then
      return
    end
    vim.api.nvim_win_call(window, function()
      local view = vim.fn.winsaveview()
      local line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(window))
      local height = vim.api.nvim_win_get_height(window)
      local max_topline = math.max(1, line_count - height + 1)
      view.topline = math.max(1, math.min(max_topline, view.topline + delta_lines))
      view.lnum = math.max(1, math.min(line_count, view.lnum + delta_lines))
      view.col = 0
      view.leftcol = 0
      vim.fn.winrestview(view)
    end)
  end
  state.refresh = refresh
  state.ensure_page = ensure_next_page
  state.load_description = ensure_description
  state.select_source = function(index)
    M.set_source(state, index)
    if options.surface and options.surface.selector then
      options.surface.selector.set_selected(state.source_index)
    end
    if options.surface and options.surface.panes.list.header.set_value then
      options.surface.panes.list.header.set_value(state.display_query, false)
    end
    state.apply_filter(state.display_query)
  end
  state.apply_filter = function(value)
    query_generation = query_generation + 1
    M.set_query(state, value)
    refresh()
    query_debouncer:schedule(value, query_generation)
  end
  state.return_to_list = function()
    if options.surface and options.surface.focus("list") and state.refresh then
      state.refresh()
    end
  end
  keymap.map(buffer, "n", "next_item", function()
    local column = cursor_column()
    M.move(state, 1)
    refresh(column)
  end, "Next pull request")
  keymap.map(buffer, "n", "previous_item", function()
    local column = cursor_column()
    M.move(state, -1)
    refresh(column)
  end, "Previous pull request")
  keymap.map(buffer, "n", "next_tab", function()
    state.select_source((state.source_index % #sources) + 1)
  end, "Next pull request source")
  keymap.map(buffer, "n", "previous_tab", function()
    state.select_source(((state.source_index - 2) % #sources) + 1)
  end, "Previous pull request source")
  keymap.map(buffer, "n", "scroll_preview_down", function()
    local window = preview_window()
    local height = window and vim.api.nvim_win_get_height(window) or 1
    scroll_preview(math.max(1, math.floor(height / 2)))
  end, "Scroll pull request description down")
  keymap.map(buffer, "n", "scroll_preview_up", function()
    local window = preview_window()
    local height = window and vim.api.nvim_win_get_height(window) or 1
    scroll_preview(-math.max(1, math.floor(height / 2)))
  end, "Scroll pull request description up")
  keymap.map(buffer, "n", "focus_preview", function()
    if options.surface then
      options.surface.focus("preview")
      return
    end
    local window = preview_window()
    if window and vim.api.nvim_win_is_valid(window) then
      ui.cursor.set_window(window, "accent")
      ui.cursor.focus(window)
      local line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(window))
      local row = math.max(1, math.min(line_count, 3))
      pcall(vim.api.nvim_win_set_cursor, window, { row, 0 })
    end
  end, "Focus pull request preview")
  keymap.map(buffer, "n", "return_to_list", state.return_to_list, "Return to pull request list")
  keymap.map(options.surface and options.surface.panes.preview.buffer or buffer, "n", "return_to_list", state.return_to_list, "Return to pull request list")
  keymap.bind_common_buffer(options.surface and options.surface.panes.preview.buffer or buffer, {
    on_quit = options.on_quit or function()
      dispose_debouncers()
      if options.surface and options.surface.close then
        options.surface.close()
      else
        vim.cmd("tabclose")
      end
    end,
  })
  keymap.map(buffer, "n", "open", function()
    if options.on_open then
      options.on_open(M.selected(state))
    end
  end, "Open pull request")
  if options.surface and options.surface.panes.list.header then
    keymap.map(buffer, "n", "edit_filter", function()
      options.surface.panes.list.header.focus(true)
    end, "Edit pull request filters")
  end
  if options.surface then
    keymap.bind_common_buffer(buffer, {
      on_quit = options.on_quit or function()
        dispose_debouncers()
        if options.surface.close then
          options.surface.close()
        else
          vim.cmd("tabclose")
        end
      end,
    })
  else
    keymap.bind_common_workspace(options.workspace, {
      on_quit = options.on_quit or function()
        dispose_debouncers()
        ui.close_workspace(options.workspace)
      end,
    })
  end
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    buffer = buffer,
    once = true,
    callback = dispose_debouncers,
  })
  refresh()
  if options.on_page and not state.page_loaded then
    load_page({ replace = true })
  end
end

function M.open(state, options)
  options = options or {}
  local mode = options.mode or "surface"
  local left_width, right_width = layout_widths(vim.o.columns)
  if mode == "surface" then
    local initial_width = math.floor(vim.o.columns * 0.48)
    local surface = ui.open_pair({
      title = "proud: pull requests",
      statusline = "pull requests",
      panes = {
        {
          name = "list",
          buffer_name = "proud://prs/list",
          title = "proud: pull requests",
          view = M.render_list(state, { width = initial_width }),
          top_pad = 2,
          cursor = "hidden",
          header = {
            buffer_name = "proud://headers/list",
            title = "pull request filters",
            prompt = "PR > ",
            placeholder = "...",
            prompt_segments = {
              { text = "PR", group = "ProudAccentText" },
              { text = " > ", group = "ProudBorder" },
            },
            value_group = "ProudBright",
            placeholder_group = "ProudMuted",
            value = state.display_query,
            trailing_segments = count_segments(state),
            on_change = function(value)
              if state.apply_filter then
                state.apply_filter(value)
              end
            end,
            on_submit = function()
              if state.return_to_list then
                state.return_to_list()
              end
            end,
          },
          separator = "ProudBorder",
          separator_buffer_name = "proud://headers/list-separator",
        },
        {
          name = "preview",
          buffer_name = "proud://prs/preview",
          title = "Preview",
          view = M.render_preview(state, { width = initial_width }),
          top_pad = 2,
          cursor = "accent",
          focus_row = 3,
          decorate = {
            cursor_group = "ProudAccent",
            float_border = "ProudPreviewBorder",
            float_title = "ProudPreviewTitle",
          },
          header = {
            buffer_name = "proud://headers/preview",
            title = "preview",
            text = "Preview",
            text_group = "ProudPreviewBorder",
            border_group = "ProudPreviewBorder",
            focusable = false,
          },
          separator = "ProudBorder",
          separator_buffer_name = "proud://headers/preview-separator",
        },
      },
      selector = {
        items = M.sources(),
        selected = state.source_index,
      },
      on_close = function()
        if state.dispose_debouncers then
          state.dispose_debouncers()
        end
      end,
      on_resize = function()
        if state.refresh then
          state.refresh()
        end
      end,
    })
    state.surface = surface
    state.window = surface.panes.list.window
    state.preview_window = surface.panes.preview.window
    state.preview_buffer = surface.panes.preview.buffer
    M.attach(surface.panes.list.buffer, state, vim.tbl_extend("force", options, { surface = surface }))
    return surface.panes.list.buffer
  end
  local workspace = ui.open_workspace("proud://prs", {
    {
      name = "list",
      buffer_name = "proud://prs/list",
      title = "proud: pull requests",
      view = M.render_list(state, { width = left_width }),
      weight = 0.44,
    },
    {
      name = "preview",
      buffer_name = "proud://prs/preview",
      title = "proud: pull requests",
      view = M.render_preview(state, { width = right_width }),
      weight = 0.56,
    },
  }, {
    focus = "list",
    title = "proud: pull requests",
    statusline = "proud  pull requests",
    on_resize = function()
      if state.refresh then
        state.refresh()
      end
    end,
  })
  state.workspace = workspace
  state.window = ui.workspace_window(workspace, "list")
  state.preview_window = ui.workspace_window(workspace, "preview")
  state.preview_buffer = ui.workspace_buffer(workspace, "preview")
  local buffer = ui.workspace_buffer(workspace, "list")
  M.attach(buffer, state, vim.tbl_extend("force", options or {}, { workspace = workspace }))
  return buffer
end

return M
