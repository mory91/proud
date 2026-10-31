return function(test)
  local feature = require("proud.loader").load("pull_request_browser")
  local fixtures = require("proud.fixtures")
  local keymap = require("proud.keymap")
  local ui = require("proud.ui")
  keymap.setup({ next_item = "J", previous_item = "K", open = "<CR>", help = "<F1>", quit = "<F4>" })
  local original_layout = ui.layout_config()
  local original_columns = vim.o.columns
  vim.o.columns = 120
  ui.configure({ windows = { margin = { top = 3, bottom = 4 }, gap = 4 } })
  local opened
  local query_calls = 0
  local last_query
  local state = feature.create(fixtures.pull_requests, { query = "is:open" })
  local buffer = feature.open(state, {
    query_debounce_ms = 15,
    on_query = function(query, callback)
      query_calls = query_calls + 1
      last_query = query
      callback(true, fixtures.pull_requests)
    end,
    on_open = function(pull)
      opened = pull.number
    end,
  })
  vim.api.nvim_win_set_cursor(state.surface.panes.list.window, { 3, 12 })
  vim.api.nvim_feedkeys("J", "x", false)
  test.eq(12, vim.api.nvim_win_get_cursor(state.surface.panes.list.window)[2], "next selection preserves the cursor column")
  local selected_lines = vim.api.nvim_buf_get_lines(buffer, 4, 6, false)
  test.eq(2, #selected_lines, "one PR occupies two adjacent rows")
  test.matches(selected_lines[1], "^▌", "one move renders the selected PR title")
  test.matches(selected_lines[2], "^▌", "the same move renders its complete subtitle")
  test.contains(selected_lines[2], "dev-lee · 5h · +58-22 · 1 thread · Review request", "title and subtitle use the dot-separated metadata format")
  local list_header = state.surface.panes.list.header
  test.eq("3/3", list_header.get_trailing_text(), "header starts with the compact visible/source count")
  local preview_window = state.surface.panes.preview.window
  local preview_buffer = state.surface.panes.preview.buffer
  test.truthy(vim.api.nvim_win_get_config(preview_window).focusable, "preview is focusable for cursor exploration")
  local selected_pull = state.filtered[state.cursor]
  local original_body = selected_pull.body
  local long_body = {}
  for index = 1, 30 do
    table.insert(long_body, ("description line %d for preview scrolling"):format(index))
  end
  selected_pull.body = table.concat(long_body, "\n")
  selected_pull.description_loaded = true
  state.refresh()
  local preview_lines = vim.api.nvim_buf_get_lines(preview_buffer, 0, -1, false)
  test.contains(table.concat(preview_lines, "\n"), "description line 1 for preview", "preview begins with the first PR description line")
  test.contains(table.concat(preview_lines, "\n"), "description line 30 for preview", "preview buffer retains the full PR description")
  test.truthy(not table.concat(preview_lines, "\n"):find("## Summary", 1, true), "preview does not generate a Summary section")
  local preview_before_scroll = vim.api.nvim_win_call(preview_window, function()
    return vim.fn.winsaveview()
  end)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-d>", true, false, true), "x", false)
  local preview_after_down = vim.api.nvim_win_call(preview_window, function()
    return vim.fn.winsaveview()
  end)
  test.truthy(
    preview_after_down.topline > preview_before_scroll.topline,
    "configured key scrolls the long PR description down"
      .. " (topline " .. preview_before_scroll.topline .. " -> " .. preview_after_down.topline .. ")"
  )
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-u>", true, false, true), "x", false)
  local preview_after_up = vim.api.nvim_win_call(preview_window, function()
    return vim.fn.winsaveview()
  end)
  test.eq(preview_before_scroll.topline, preview_after_up.topline, "configured key scrolls the PR description back up")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-p>", true, false, true), "x", false)
  test.eq(preview_window, vim.api.nvim_get_current_win(), "focus action moves the cursor into the preview")
  test.eq("ProudAccent", vim.wo[preview_window].winhighlight:match("Cursor:ProudAccent") and "ProudAccent", "preview cursor uses the accent color")
  local preview_cursor = vim.api.nvim_win_get_cursor(preview_window)
  test.eq(3, preview_cursor[1], "preview cursor starts below the preview header")
  vim.api.nvim_feedkeys("j", "x", false)
  test.eq(4, vim.api.nvim_win_get_cursor(preview_window)[1], "ordinary Neovim motion explores preview text")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-l>", true, false, true), "x", false)
  test.eq(state.surface.panes.list.window, vim.api.nvim_get_current_win(), "return action moves back to the PR list")
  selected_pull.body = original_body
  state.refresh()
  list_header.set_value("one", true)
  test.eq("one", list_header.get_value(), "filters are edited directly in the PR header")
  state.apply_filter("one")
  state.apply_filter("one two")
  state.apply_filter("one two three")
  test.eq(0, query_calls, "rapid filter edits do not call the API immediately")
  test.truthy(vim.wait(250, function()
    return query_calls == 1
  end, 10), "debounced filter edits settle into one API request")
  test.eq("one two three", last_query, "the debounced request uses the latest filter")
  state.apply_filter("is:open")
  test.truthy(vim.wait(250, function()
    return query_calls == 2
  end, 10), "the restored query is refreshed after the debounce window")
  test.eq("3/3", list_header.get_trailing_text(), "restored filters update the visible count")
  state.apply_filter("label:capture")
  test.eq("1/3", list_header.get_trailing_text(), "filter edits update the count immediately")
  state.pulls = { fixtures.pull_requests[2] }
  state.query = "label:capture"
  feature.filter(state)
  state.refresh()
  test.eq("1/3", list_header.get_trailing_text(), "source result subsets do not erase the source total")
  state.pulls = fixtures.pull_requests
  state.apply_filter("is:open")
  test.eq("3/3", list_header.get_trailing_text(), "the source count remains stable after restoring the source")
  state.return_to_list()
  vim.api.nvim_feedkeys("K", "x", false)
  test.eq(12, vim.api.nvim_win_get_cursor(state.surface.panes.list.window)[2], "previous selection preserves the cursor column")
  vim.api.nvim_feedkeys("J", "x", false)
  vim.api.nvim_win_set_height(state.surface.panes.list.window, 5)
  vim.api.nvim_win_set_cursor(state.surface.panes.list.window, { 6, 12 })
  vim.api.nvim_win_call(state.surface.panes.list.window, function()
    vim.fn.winrestview({ topline = 4, lnum = 6, col = 12 })
  end)
  vim.api.nvim_feedkeys("J", "x", false)
  local scroll_view = vim.api.nvim_win_call(state.surface.panes.list.window, function()
    return vim.fn.winsaveview()
  end)
  test.truthy(
    scroll_view.topline <= 5 and scroll_view.topline + 2 <= 7 and scroll_view.topline + 4 >= 8,
    "one move reveals the full two-row item below the in-window header"
  )
  state.cursor = 3
  ui.set_cursor(state.surface.panes.list.buffer, 7, 12, 8, { reserved_rows = 2 })
  vim.api.nvim_win_call(state.surface.panes.list.window, function()
    vim.fn.winrestview({ topline = 2, lnum = 7, col = 12 })
  end)
  vim.api.nvim_feedkeys("K", "x", false)
  local upward_view = vim.api.nvim_win_call(state.surface.panes.list.window, function()
    return vim.fn.winsaveview()
  end)
  test.eq(2, state.cursor, "upward selection reaches the preceding pull request")
  test.truthy(
    5 > upward_view.topline + 1 and 6 > upward_view.topline + 1,
    "upward selection keeps the two-row pull request below the in-window header"
      .. " (topline " .. upward_view.topline .. ")"
  )
  state.cursor = 3
  ui.set_cursor(state.surface.panes.list.buffer, 7, 12, 8, { reserved_rows = 2 })
  vim.api.nvim_feedkeys("K", "x", false)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
  test.eq(2, state.cursor, "configured next binding moves selection")
  test.eq(479, opened, "configured open binding launches the selected pull request")
  local provider = require("proud.provider")
  local util = require("proud.util")
  local relative_now = assert(util.parse_iso8601("2026-10-15T12:00:00Z"))
  local raw_pulls = {}
  local raw_ages = { "24m", "1h", "1d" }
  local raw_created = {
    "2026-10-15T11:36:00Z",
    "2026-10-15T11:00:00Z",
    "2026-10-14T12:00:00Z",
  }
  for index, count in ipairs({ 3, 1, 0 }) do
    table.insert(raw_pulls, provider.normalize_pull_request({
      number = 900 + index,
      title = "Raw API review thread count " .. index,
      author = { login = "api-author-" .. index },
      createdAt = raw_created[index],
      additions = 77,
      deletions = 9,
      reviewDecision = "REVIEW_REQUIRED",
      labels = { nodes = { { name = "api" } } },
      reviewThreads = { totalCount = count },
    }, { now = relative_now }))
  end
  local raw_state = feature.create(raw_pulls, { query = "" })
  local raw_view = feature.render_list(raw_state, { width = 64 })
  test.eq(raw_ages, vim.tbl_map(function(pull)
    return pull.age
  end, raw_pulls), "E2E normalizes raw API timestamps into relative ages")
  test.contains(raw_view.lines[2], "3 threads", "E2E renders three raw API review threads")
  test.contains(raw_view.lines[4], "1 thread", "E2E renders one raw API review thread")
  test.contains(raw_view.lines[6], "no threads", "E2E renders zero raw API review threads")
  test.truthy(vim.api.nvim_buf_is_valid(buffer))
  test.truthy(state.surface, "browser uses native rounded half-windows")
  test.eq(2, #state.surface.order, "surface exposes list and preview halves")
  test.eq(buffer, state.surface.panes.list.buffer, "both halves render in one buffer")
  test.truthy(state.surface.panes.preview.buffer ~= buffer, "preview is its own native window buffer")
  test.truthy(vim.api.nvim_win_is_valid(state.surface.panes.list.window), "list is a native window")
  test.truthy(vim.api.nvim_win_is_valid(state.surface.panes.preview.window), "preview is a native window")
  test.eq(false, vim.wo[state.surface.panes.list.window].cursorline, "browser list uses only the purple cursor rail")
  test.eq(false, vim.wo[state.surface.panes.preview.window].cursorline, "browser preview has no row-wide cursor highlight")
  test.contains(vim.wo[state.surface.panes.list.window].winhighlight, "Cursor:ProudCursorHidden", "browser list hides the native cursor")
  test.contains(vim.wo[state.surface.panes.preview.window].winhighlight, "Cursor:ProudAccent", "browser preview exposes the accent cursor")
  test.contains(vim.wo[state.surface.panes.list.window].winhighlight, "Normal:ProudBackground", "list uses the shared base background")
  test.contains(vim.wo[state.surface.panes.preview.window].winhighlight, "Normal:ProudBackground", "preview uses the shared base background")
  test.contains(vim.wo[state.surface.panes.list.header.window].winhighlight, "Normal:ProudBackground", "list header uses the shared base background")
  test.contains(vim.wo[state.surface.panes.preview.header.window].winhighlight, "Normal:ProudBackground", "preview header uses the shared base background")
  test.contains(vim.o.guicursor, "ProudCursorHidden", "browser uses the TUI hidden cursor style")
  test.eq(100, require("proud.palette").groups().ProudCursorHidden.blend, "hidden cursor uses TUI blend hiding")
  local list_config = vim.api.nvim_win_get_config(state.surface.panes.list.window)
  local preview_config = vim.api.nvim_win_get_config(state.surface.panes.preview.window)
  local preview_header = state.surface.panes.preview.header
  local list_header_config = vim.api.nvim_win_get_config(list_header.window)
  local preview_header_config = vim.api.nvim_win_get_config(preview_header.window)
  local list_separator = state.surface.panes.list.header_separator
  local preview_separator = state.surface.panes.preview.header_separator
  test.truthy(not list_config.title or list_config.title == "", "list window has no native title")
  test.truthy(not preview_config.title or preview_config.title == "", "preview window has no native title")
  test.eq("prompt", vim.bo[list_header.buffer].buftype, "PR filter header is editable in-page")
  test.contains(vim.api.nvim_buf_get_lines(list_header.buffer, 0, 1, false)[1], "PR > ", "PR header shows the filter prompt")
  test.contains(vim.api.nvim_buf_get_lines(preview_header.buffer, 0, 1, false)[1], "Preview", "preview header shows its title")
  test.eq(list_config.row + 1, list_header_config.row, "list header starts below the rounded top border")
  test.eq(preview_config.row + 1, preview_header_config.row, "preview header starts below the rounded top border")
  test.eq(list_config.col + 1, list_header_config.col, "list header stays between the vertical borders")
  test.eq(preview_config.col + 1, preview_header_config.col, "preview header stays between the vertical borders")
  test.eq(list_config.row + 2, vim.api.nvim_win_get_config(list_separator.window).row, "list separator is the second interior row")
  test.eq(preview_config.row + 2, vim.api.nvim_win_get_config(preview_separator.window).row, "preview separator is the second interior row")
  test.eq(list_config.col + 1, vim.api.nvim_win_get_config(list_separator.window).col, "list separator stays between the vertical borders")
  test.eq(preview_config.col + 1, vim.api.nvim_win_get_config(preview_separator.window).col, "preview separator stays between the vertical borders")
  test.eq(string.rep("─", list_config.width), vim.api.nvim_buf_get_lines(list_separator.buffer, 0, 1, false)[1], "list separator spans the pane")
  test.eq(string.rep("─", preview_config.width), vim.api.nvim_buf_get_lines(preview_separator.buffer, 0, 1, false)[1], "preview separator spans the pane")
  local namespace = vim.api.nvim_get_namespaces().proud
  local function separator_has_one_full_color(separator, group)
    local line = vim.api.nvim_buf_get_lines(separator.buffer, 0, 1, false)[1] or ""
    local marks = vim.api.nvim_buf_get_extmarks(separator.buffer, namespace, 0, -1, { details = true })
    if #marks ~= 1 then
      return false
    end
    local detail = marks[1][4] or {}
    local expected_group = vim.api.nvim_get_hl_id_by_name(group)
    return detail.end_col == #line
      and (detail.hl_group == group or detail.hl_group == expected_group)
  end
  test.truthy(separator_has_one_full_color(list_separator, "ProudBorder"), "list separator has one full-line color")
  test.truthy(separator_has_one_full_color(preview_separator, "ProudBorder"), "preview separator has one full-line color")
  for _, reserved_line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, 2, false)) do
    test.matches(reserved_line, "^ +$", "header and separator reserve padded body rows")
  end
  test.eq({ "╭", "─", "╮", "│", "╯", "─", "╰", "│" }, list_config.border, "list window uses Neovim rounded border")
  test.eq({ "╭", "─", "╮", "│", "╯", "─", "╰", "│" }, preview_config.border, "preview window uses Neovim rounded border")
  test.eq("editor", list_config.relative, "list window is positioned in the editor")
  test.eq("editor", preview_config.relative, "preview window is positioned in the editor")
  test.truthy(list_config.col >= 2 and list_config.row >= 1, "list window keeps outer margins")
  test.truthy(preview_config.col + preview_config.width <= vim.o.columns - 1, "preview window keeps right margin")
  test.eq(4, preview_config.col - (list_config.col + list_config.width), "configured gap separates the native windows")
  local top_chrome = (vim.o.showtabline == 2 or (vim.o.showtabline == 1 and vim.fn.tabpagenr("$") > 1)) and 1 or 0
  local bottom_chrome = vim.o.cmdheight + (vim.o.laststatus > 0 and 1 or 0)
  local statusline_start = vim.o.lines - bottom_chrome
  for _, pane_config in ipairs({ list_config, preview_config }) do
    test.truthy(pane_config.row - 1 >= top_chrome + 3, "window border keeps the configured top margin")
    test.truthy(pane_config.row + pane_config.height + 1 <= statusline_start - 4, "window border stays clear of the statusline")
  end
  test.contains(vim.wo[state.surface.panes.list.window].winhighlight, "FloatBorder:ProudAccentText", "float border is purple")
  test.contains(vim.wo[state.surface.panes.preview.window].winhighlight, "FloatBorder:ProudPreviewBorder", "preview border is muted grey")
  test.contains(vim.wo[state.surface.panes.preview.window].winhighlight, "FloatTitle:ProudPreviewTitle", "preview title is muted grey")
  test.eq(35, require("proud.palette").groups().ProudPreviewBorder.blend, "preview border uses low opacity")
  vim.cmd("silent! tabclose!")

  local page_requests = {}
  local description_requests = {}
  local lazy_pulls = {}
  for index = 1, 40 do
    table.insert(lazy_pulls, {
      number = 8000 + index,
      title = "Paginated pull request " .. index,
      author = { login = "page-author-" .. index },
      age = index .. "m",
      additions = index,
      deletions = 1,
      threads = 0,
      review_decision = "REVIEW_REQUIRED",
    })
  end
  local lazy_state = feature.create({}, { query = "is:open" })
  feature.open(lazy_state, {
    query_debounce_ms = 15,
    description_debounce_ms = 100,
    on_page = function(page, callback)
      table.insert(page_requests, page)
      local offset = page.after == "" and 0 or tonumber(page.after) or 0
      local items = {}
      for index = offset + 1, math.min(offset + page.limit, #lazy_pulls) do
        table.insert(items, vim.deepcopy(lazy_pulls[index]))
      end
      callback(true, {
        pulls = items,
        total_count = #lazy_pulls,
        has_next_page = offset + #items < #lazy_pulls,
        next_cursor = tostring(offset + #items),
      })
    end,
    on_description = function(number, callback)
      table.insert(description_requests, number)
      callback(true, "Lazy description for #" .. number)
    end,
  })
  test.truthy(vim.wait(500, function()
    return lazy_state.page_loaded and lazy_state.filtered[1] and lazy_state.filtered[1].description_loaded
  end, 10), "initial page and preselected description load asynchronously")
  local expected_page_size = feature.page_size_for_height(vim.api.nvim_win_get_height(lazy_state.window))
  test.eq(expected_page_size, page_requests[1].limit, "initial API page size matches complete visible items")
  test.eq(expected_page_size, #lazy_state.pulls, "opening fetches only one visible page")
  test.eq({ 8001 }, description_requests, "opening fetches only the preselected description")
  for _ = 2, math.max(2, expected_page_size - 1) do
    feature.move(lazy_state, 1)
    lazy_state.refresh()
  end
  test.eq({ 8001 }, description_requests, "held cursor movement does not fetch every intermediate description")
  test.truthy(vim.wait(300, function()
    return #description_requests == 2
  end, 10), "description request settles after cursor movement stops")
  test.eq(lazy_state.filtered[lazy_state.cursor].number, description_requests[2], "settled cursor fetches only its description")
  test.truthy(vim.wait(300, function()
    return #lazy_state.pulls == expected_page_size * 3
  end, 10), "first selection movement prefetches two additional cursor pages")
  test.eq(3, #page_requests, "pagination sends exactly two prefetch requests")
  test.eq(tostring(expected_page_size), page_requests[2].after, "pagination resumes from the API cursor")
  test.eq(tostring(expected_page_size * 2), page_requests[3].after, "prefetch requests stay sequential")

  local selector = lazy_state.surface.selector
  test.truthy(selector, "rounded-window framework exposes the outside source selector")
  local selector_config = vim.api.nvim_win_get_config(selector.window)
  local selector_lines = vim.api.nvim_buf_get_lines(selector.buffer, 0, -1, false)
  test.eq(1, selector_config.height, "source buttons use a one-row solid button bar")
  test.eq(1, #selector_lines, "source buttons have no outline rows")
  test.truthy(selector_lines[1]:find("╭", 1, true) == nil and selector_lines[1]:find("╰", 1, true) == nil, "source buttons have no outline")
  local selector_namespace = vim.api.nvim_get_namespaces().proud
  local selector_marks = vim.api.nvim_buf_get_extmarks(selector.buffer, selector_namespace, 0, -1, { details = true })
  local accent_id = vim.api.nvim_get_hl_id_by_name("ProudAccent")
  local inactive_id = vim.api.nvim_get_hl_id_by_name("ProudMuted")
  local solid_active_button = false
  local solid_inactive_button = false
  for _, mark in ipairs(selector_marks) do
    local detail = mark[4] or {}
    local text = selector_lines[1]:sub((detail.col or mark[3]) + 1, detail.end_col or mark[3])
    if (detail.hl_group == "ProudAccent" or detail.hl_group == accent_id) and text:find("All open", 1, true) then
      solid_active_button = (detail.end_col or mark[3]) - (detail.col or mark[3]) >= #"  All open  "
    elseif (detail.hl_group == "ProudMuted" or detail.hl_group == inactive_id) and text:find("Mine", 1, true) then
      solid_inactive_button = (detail.end_col or mark[3]) - (detail.col or mark[3]) >= #" Mine "
    end
  end
  test.truthy(solid_active_button, "active source fills the entire button background")
  test.truthy(solid_inactive_button, "inactive source uses muted text without a separate background")
  test.eq(3, selector.get_selected(), "All open is the default selected source")
  local selector_text = table.concat(vim.api.nvim_buf_get_lines(selector.buffer, 0, -1, false), "\n")
  for _, label in ipairs({ "Review requested", "Mine", "All open", "Recently viewed", "Branches" }) do
    test.contains(selector_text, label, "source selector shows " .. label)
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "x", false)
  test.eq(4, selector.get_selected(), "next-source keymap selects Recently viewed")
  test.eq("is:open interacted-by:@me sort:updated-desc", lazy_state.display_query, "source movement updates the PR query")
  test.eq(
    "is:open interacted-by:@me sort:updated-desc",
    lazy_state.surface.panes.list.header.get_value(),
    "source movement updates the editable PR filter"
  )
  test.truthy(vim.wait(100, function()
    return #page_requests == 4
  end, 10), "source movement reloads the PR list")
  test.eq("is:open interacted-by:@me sort:updated-desc", page_requests[4].query)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<S-Tab>", true, false, true), "x", false)
  test.eq(3, selector.get_selected(), "previous-source keymap returns to All open")
  test.eq("is:open", lazy_state.display_query, "previous source restores its PR query")
  test.truthy(vim.wait(100, function()
    return #page_requests == 5
  end, 10), "previous source reloads the PR list after debounce")
  test.eq("is:open", page_requests[5].query)
  for _ = 1, 5 do
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "x", false)
  end
  test.eq(3, selector.get_selected(), "rapid source movement wraps back to All open")
  test.eq("is:open", lazy_state.display_query, "rapid source movement keeps the final query")
  test.truthy(vim.wait(100, function()
    return #page_requests == 6
  end, 10), "rapid source movement coalesces into one list request")
  test.eq(6, #page_requests, "rapid source movement does not fetch intermediate sources")
  test.eq("is:open", page_requests[6].query, "rapid source movement fetches only the settled query")
  vim.cmd("silent! tabclose!")
  test.truthy(not lazy_state.query_debouncer.pending(), "closing the browser cancels pending query work")
  test.truthy(not lazy_state.description_debouncer.pending(), "closing the browser cancels pending description work")

  local replace_requests = {}
  local pending_initial
  local replace_state = feature.create({}, { query = "old", display_query = "old" })
  feature.open(replace_state, {
    query_debounce_ms = 15,
    on_page = function(page, callback)
      table.insert(replace_requests, page)
      if #replace_requests == 1 then
        pending_initial = callback
        return
      end
      callback(true, {
        pulls = { { number = 9001, title = "New query result" } },
        total_count = 1,
        has_next_page = false,
      })
    end,
    on_description = function(_, callback)
      callback(true, "New query description")
    end,
  })
  replace_state.apply_filter("new")
  test.truthy(vim.wait(100, function()
    return pending_initial ~= nil
  end, 10), "stale first-page request remains in flight")
  pending_initial(true, {
    pulls = { { number = 9000, title = "Old query result" } },
    total_count = 1,
    has_next_page = false,
  })
  test.truthy(vim.wait(250, function()
    return #replace_requests == 2 and replace_state.page_loaded
  end, 10), "a newer filter request supersedes an older in-flight page")
  test.eq("new", replace_requests[2].query)
  test.eq("", replace_requests[2].after, "the replacement query restarts at the first cursor page")
  test.eq(1, #replace_state.pulls)
  test.eq("New query result", replace_state.pulls[1].title)
  vim.cmd("silent! tabclose!")

  ui.configure(original_layout)
  vim.o.columns = original_columns
  keymap.setup()
end
