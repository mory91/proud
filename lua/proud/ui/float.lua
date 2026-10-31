local ui_header = require("proud.ui.header")
local ui_render = require("proud.ui.render")
local ui_window = require("proud.ui.window")

local M = {}

function M.open_float(view, name, options)
  options = options or {}
  vim.o.guicursor = ui_window.default_guicursor
  local width = options.width or math.min(vim.o.columns - 8, 132)
  local height = options.height or math.min(vim.o.lines - 8, 34)
  local row = options.row or math.floor((vim.o.lines - height) / 2)
  local col = options.col or math.floor((vim.o.columns - width) / 2)
  local buffer = ui_window.buffer(name)
  local window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
  })
  vim.wo[window].winhighlight = "NormalFloat:ProudBackground,FloatBorder:ProudAccent"
  vim.wo[window].wrap = false
  vim.wo[window].cursorline = true
  vim.b[buffer].proud_title = ui_window.title_for(name)
  vim.wo[window].statusline = "%#ProudAccent# PROUD %#ProudPanel# Help available"
  ui_render.render(buffer, view)
  local header = options.header and ui_header.open(window, options.header) or nil
  return buffer, window, header
end

return M
