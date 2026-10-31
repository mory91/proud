local session = require('proud.session')
local state = session.current and session.current.state
local surface = state and state.surface
local preview = surface and surface.panes and surface.panes.preview
local list = surface and surface.panes and surface.panes.list
if not preview or not list then
  vim.api.nvim_echo({ { 'PREVIEW_FOCUS_OK=false missing' } }, false, {})
  return
end
local focused = vim.api.nvim_get_current_win() == preview.window
local cursor = vim.api.nvim_win_get_cursor(preview.window)
local config = vim.api.nvim_win_get_config(preview.window)
local highlight = vim.wo[preview.window].winhighlight or ''
local ok = focused and config.focusable == true and cursor[1] >= 3 and highlight:find('Cursor:ProudAccent', 1, true) ~= nil
vim.api.nvim_echo({ { ('PREVIEW_FOCUS_OK=%s row=%d'):format(tostring(ok), cursor[1]) } }, false, {})
