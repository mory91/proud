return function(test)
  local ui = require("proud.ui")
  local buffer = vim.api.nvim_create_buf(false, true)
  local window = vim.api.nvim_open_win(buffer, false, {
    relative = "editor", row = 1, col = 1, width = 10, height = 1, style = "minimal",
  })
  vim.wo[window].wrap = true
  vim.wo[window].number = true
  ui.window_options(window, { signcolumn = "yes" })
  test.eq(false, vim.wo[window].wrap, "window_options disables wrap")
  test.eq(false, vim.wo[window].number, "window_options disables numbers")
  test.eq("yes", vim.wo[window].signcolumn, "window_options applies overrides")

  ui.winhighlight(window, ui.cursor_groups({ Normal = "ProudBackground", FloatBorder = "ProudAccent" }, "ProudCursorHidden"))
  test.eq(
    "Cursor:ProudCursorHidden,CursorIM:ProudCursorHidden,FloatBorder:ProudAccent,Normal:ProudBackground,lCursor:ProudCursorHidden",
    vim.wo[window].winhighlight,
    "winhighlight builds a sorted, deterministic value"
  )
  vim.api.nvim_win_close(window, true)

  local named = ui.buffer("proud://test/buffer-helper")
  test.eq("nofile", vim.bo[named].buftype, "buffer defaults to nofile")
  test.eq("hide", vim.bo[named].bufhidden, "buffer defaults to bufhidden=hide")
  test.eq(false, vim.bo[named].modifiable, "buffer defaults to read-only")
  test.eq(named, ui.buffer("proud://test/buffer-helper"), "buffer reuses an existing name")
  local wiped = ui.buffer(nil, { bo = { bufhidden = "wipe", modifiable = true } })
  test.truthy(wiped ~= named, "unnamed buffers are always new")
  test.eq("wipe", vim.bo[wiped].bufhidden, "bo overrides defaults")
  test.eq(true, vim.bo[wiped].modifiable, "bo can make a buffer editable")
  vim.api.nvim_buf_delete(named, { force = true })
  vim.api.nvim_buf_delete(wiped, { force = true })

  local window_module = require("proud.ui.window")
  test.eq("pr/482/overview", window_module.title_for("proud://pr/482/overview"), "fallback title strips the scheme")
  local previous = window_module.status_segments
  ui.set_status_segments({ { " status ", "ProudMuted" } })
  local status_buffer = ui.buffer("proud://test/status")
  local status_window = vim.api.nvim_open_win(status_buffer, false, {
    relative = "editor", row = 1, col = 1, width = 20, height = 1, style = "minimal",
  })
  window_module.decorate(status_window, status_buffer, "proud://test/status", { title = "t" })
  test.contains(vim.wo[status_window].statusline, "%#ProudMuted# status ", "statusline shows configured segments")
  ui.set_status_segments({})
  window_module.decorate(status_window, status_buffer, "proud://test/status", { title = "t" })
  test.truthy(not vim.wo[status_window].statusline:find("GitHub", 1, true), "framework adds no GitHub status by default")
  window_module.set_status_segments(previous)
  vim.api.nvim_win_close(status_window, true)
  vim.api.nvim_buf_delete(status_buffer, { force = true })

  local render_buffer = ui.buffer("proud://test/render-offset")
  local view = { lines = { "abc", "line\nbreak" }, highlights = { 1, 0, 4, "ProudMuted" }, highlight_format = "flat" }
  ui.render(render_buffer, view, { top_pad = 2 })
  test.eq(4, vim.api.nvim_buf_line_count(render_buffer), "top_pad adds blank rows")
  test.eq("   ", vim.api.nvim_buf_get_lines(render_buffer, 0, 1, false)[1], "pad rows match the first line width")
  test.eq("line break", vim.api.nvim_buf_get_lines(render_buffer, 3, 4, false)[1], "newlines become spaces")
  test.eq(1, view.highlights[1], "rendering with top_pad does not modify the view")
  local marks = vim.api.nvim_buf_get_extmarks(render_buffer, -1, 0, -1, { details = true })
  test.eq(1, #marks, "one highlight is placed")
  test.eq(3, marks[1][2], "highlight rows are offset by top_pad")
  vim.api.nvim_buf_delete(render_buffer, { force = true })
end
