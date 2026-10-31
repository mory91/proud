local state = require("proud.session").current.state
local surface = state and state.surface
local before = vim.json.decode(vim.g.PROUD_LAYOUT_SNAPSHOT or "{}")
local expected_columns = tonumber(vim.g.PROUD_EXPECTED_COLUMNS)
local expected_lines = tonumber(vim.g.PROUD_EXPECTED_LINES)
local expected_width = tonumber(vim.g.PROUD_EXPECTED_WIDTH)
local expected_height = tonumber(vim.g.PROUD_EXPECTED_HEIGHT)
local list = surface and surface.panes and surface.panes.list
local preview = surface and surface.panes and surface.panes.preview
if not list or not preview or not expected_columns or not expected_lines then
  vim.api.nvim_echo({ { "RESIZE_CHANGED_OK=false missing" } }, false, {})
  return
end
vim.cmd("doautocmd VimResized")
local after = vim.api.nvim_win_get_config(list.window)
local preview_config = vim.api.nvim_win_get_config(preview.window)
local list_line = vim.api.nvim_buf_get_lines(list.buffer, 0, 1, false)[1] or ""
local ok = vim.o.columns == expected_columns
  and vim.o.lines == expected_lines
  and after.width == expected_width
  and after.height == expected_height
  and after.width ~= before.width
  and after.height ~= before.height
  and preview_config.width ~= after.width
  and vim.fn.strdisplaywidth(list_line) == after.width
  and list.header.get_trailing_text() ~= ""
vim.api.nvim_echo({ { ("RESIZE_CHANGED_OK=%s actual=%dx%d expected=%dx%d terminal=%dx%d line=%d header=%s"):format(
  tostring(ok),
  after.width,
  after.height,
  expected_width or -1,
  expected_height or -1,
  vim.o.columns,
  vim.o.lines,
  vim.fn.strdisplaywidth(list_line),
  tostring(list.header.get_trailing_text())
) } }, false, {})
