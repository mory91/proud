local session = require('proud.session')
local state = session.current and session.current.state
local surface = state and state.surface
local list = surface and surface.panes and surface.panes.list
local ok = list and vim.api.nvim_get_current_win() == list.window
vim.api.nvim_echo({ { ('PREVIEW_RETURN_OK=' .. tostring(ok)) } }, false, {})
