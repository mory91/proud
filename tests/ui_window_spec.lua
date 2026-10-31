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
end
