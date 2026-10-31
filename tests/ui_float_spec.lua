return function(test)
  local ui = require("proud.ui")
  local buffer = vim.api.nvim_create_buf(false, true)
  local place = { row = 2, col = 3, width = 20, height = 2, zindex = 60 }
  local float = ui.float.create(buffer, {
    placement = function()
      return place
    end,
  })
  test.truthy(float.is_valid(), "float opens a window")
  local config = vim.api.nvim_win_get_config(float.window)
  test.eq(20, config.width, "float uses placement width")
  test.eq(2, config.height, "float uses placement height")

  place = { row = 4, col = 5, width = 30 }
  test.truthy(float.reposition(), "reposition succeeds while open")
  config = vim.api.nvim_win_get_config(float.window)
  test.eq(30, config.width, "reposition re-reads placement width")
  test.eq(1, config.height, "reposition defaults height to 1")

  local child_buffer = vim.api.nvim_create_buf(false, true)
  local child = ui.float.create(child_buffer, {
    placement = ui.float.anchored(float.window, { row = 1, col = 1 }),
  })
  test.eq(30, vim.api.nvim_win_get_config(child.window).width, "anchored float matches parent width")
  test.eq(61, vim.api.nvim_win_get_config(child.window).zindex, "anchored float sits above its parent")

  float.close()
  test.truthy(not float.is_valid(), "close closes the window")
  test.truthy(not child.reposition(), "anchored float skips reposition once the parent is gone")
  child.close()
  test.truthy(not float.reposition(), "reposition is a no-op after close")
end
