local state = require("proud.session").current.state
local header = state.surface.panes.list.header
vim.cmd("redraw!")
local position = vim.api.nvim_win_get_position(header.window)
local row = {}
for column = position[2] + 1, position[2] + vim.api.nvim_win_get_width(header.window) do
  table.insert(row, vim.fn.screenstring(position[1] + 1, column))
end
local rendered = table.concat(row)
local expected = vim.g.PROUD_EXPECTED_COUNT or vim.env.PROUD_EXPECTED_COUNT or header.get_trailing_text()
local actual = header.get_trailing_text()
local ok = actual == expected and rendered:find(expected, 1, true) ~= nil
vim.api.nvim_echo({
  { (vim.g.PROUD_COUNT_LABEL or vim.env.PROUD_COUNT_LABEL or "COUNT_OK") .. "=" .. tostring(ok) .. " value=" .. actual .. " row=[" .. vim.trim(rendered) .. "]" },
}, false, {})
