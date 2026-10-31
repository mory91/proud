-- Public entry point of Proud's UI framework: require("proud.ui").
-- Implementation lives in focused modules under lua/proud/ui/; this file
-- re-exports the stable API so callers never depend on the module layout.
local config = require("proud.ui.config")
local float = require("proud.ui.float")
local geometry = require("proud.ui.geometry")
local header = require("proud.ui.header")
local lifecycle = require("proud.ui.lifecycle")
local render = require("proud.ui.render")
local selector = require("proud.ui.selector")
local surface = require("proud.ui.surface")
local text = require("proud.ui.text")
local text_frame = require("proud.ui.text_frame")
local themes = require("proud.ui.theme")
local window = require("proud.ui.window")
local workspace = require("proud.ui.workspace")

local M = {
  themes = themes,
  geometry = geometry,
}

local buffer_lifecycle_group = vim.api.nvim_create_augroup("ProudBufferLifecycle", { clear = true })
vim.api.nvim_create_autocmd("QuitPre", {
  group = buffer_lifecycle_group,
  callback = function()
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buffer) and vim.b[buffer].proud_buffer then
        vim.bo[buffer].modified = false
      end
    end
  end,
})

-- Themes
function M.add_theme(name, definition, options)
  return themes.register(name, definition, options)
end

function M.use_theme(name)
  return themes.use(name)
end

function M.current_theme()
  return themes.current()
end

-- Layout configuration
M.configure = config.configure
M.layout_config = config.layout_config

-- Text
M.fit = text.fit
M.wrap_text = text.wrap_text
M.content_lines = text.content_lines
M.open_text_frame = text_frame.open

-- Rendering
M.render = render.render
M.fit_view = render.fit_view

-- Scenes and windows
M.create_scene_lifecycle = lifecycle.create_scene_lifecycle
M.open_pane_header = header.open
M.button_layout = selector.button_layout
M.open_rounded_pair = surface.open_rounded_pair
M.open_float = float.open_float
M.set_cursor = window.set_cursor

-- Workspaces
M.open_workspace = workspace.open_workspace
M.resize_workspace = workspace.resize_workspace
M.render_workspace = workspace.render_workspace
M.workspace_buffer = workspace.workspace_buffer
M.workspace_window = workspace.workspace_window
M.focus_workspace_pane = workspace.focus_workspace_pane
M.close_workspace = workspace.close_workspace

return M
