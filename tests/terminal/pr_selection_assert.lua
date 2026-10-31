local state = require("proud.session").current.state
local list = state.surface.panes.list
local lines = vim.api.nvim_buf_get_lines(list.buffer, 4, 6, false)
local preview = table.concat(vim.api.nvim_buf_get_lines(state.surface.panes.preview.buffer, 0, -1, false), "\n")
local selected_subtitle = "dev-lee · 5h · +58-22 · 1 thread · Review request"
local ok = state.cursor == 2
  and #lines == 2
  and lines[1]:find("▌", 1, true) == 1
  and lines[2]:find("▌", 1, true) == 1
  and lines[2]:find(selected_subtitle, 1, true) ~= nil
  and preview:find("#479", 1, true) ~= nil
vim.api.nvim_echo({ { "SELECTED_SUBTITLE_OK=" .. tostring(ok) } }, false, {})
