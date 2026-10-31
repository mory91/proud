return function(test)
  local ui = require("proud.ui")
  local cursor = ui.cursor
  local original = vim.o.guicursor
  local home = vim.api.nvim_get_current_win()
  -- The user changes their cursor after Proud has loaded.
  vim.o.guicursor = "n:ver25"

  local buffer = ui.buffer("proud://test/cursor")
  local window = vim.api.nvim_open_win(buffer, false, {
    relative = "editor", row = 1, col = 1, width = 10, height = 1, style = "minimal",
  })
  cursor.set_window(window, "hidden")
  test.eq("n:ver25", vim.o.guicursor, "declaring a shape on a background window changes nothing")
  cursor.focus(window)
  test.eq(cursor.shapes.hidden, vim.o.guicursor, "focusing a Proud window applies its shape")
  cursor.set_window(window, "accent")
  test.eq(cursor.shapes.accent, vim.o.guicursor, "changing the current window's shape applies at once")

  vim.api.nvim_set_current_win(home)
  test.eq("n:ver25", vim.o.guicursor, "leaving Proud restores the user's current cursor, not the load-time one")

  vim.api.nvim_win_close(window, true)
  vim.api.nvim_buf_delete(buffer, { force = true })
  vim.o.guicursor = original
end
