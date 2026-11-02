-- Public entry point of Proud's UI framework: require("proud.ui").
-- Implementation lives in focused modules under lua/proud/ui/; this file
-- re-exports the stable API so callers never depend on the module layout.
local config = require("proud.ui.config")
local cursor = require("proud.ui.cursor")
local float = require("proud.ui.float")
local inline_diff = require("proud.ui.inline_diff")
local geometry = require("proud.ui.geometry")
local header = require("proud.ui.header")
local lifecycle = require("proud.ui.lifecycle")
local modal = require("proud.ui.modal")
local render = require("proud.ui.render")
local selector = require("proud.ui.selector")
local surface = require("proud.ui.surface")
local text = require("proud.ui.text")
local text_frame = require("proud.ui.text_frame")
local themes = require("proud.ui.theme")
local view = require("proud.ui.view")
local window = require("proud.ui.window")
local workspace = require("proud.ui.workspace")

local M = {
  themes = themes,
  geometry = geometry,
  float = float,
  inline_diff = inline_diff,
  cursor = cursor,
  text = text,
  view = view,
}

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
M.display_width = text.display_width
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
M.open_pair = surface.open_pair
M.open_float = modal.open_float
M.set_cursor = window.set_cursor
M.winbar = window.winbar
M.set_status_segments = window.set_status_segments
M.buffer = window.buffer
M.window_options = window.options
M.winhighlight = window.winhighlight
M.cursor_groups = window.cursor_groups

-- Workspaces
M.open_workspace = workspace.open_workspace
M.resize_workspace = workspace.resize_workspace
M.render_workspace = workspace.render_workspace
M.workspace_buffer = workspace.workspace_buffer
M.workspace_window = workspace.workspace_window
M.focus_workspace_pane = workspace.focus_workspace_pane
M.pane_visible = workspace.pane_visible
M.hide_pane = workspace.hide_pane
M.show_pane = workspace.show_pane
M.toggle_pane = workspace.toggle_pane
M.close_workspace = workspace.close_workspace

return M
