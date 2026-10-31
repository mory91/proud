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
end
