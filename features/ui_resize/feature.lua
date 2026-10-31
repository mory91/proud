local ui = require("proud.ui")
local geometry = require("proud.ui.geometry")

local M = {}

function M.surface_geometry(columns, lines, options)
  options = options or {}
  local configured = ui.layout_config()
  local windows = options.windows or {}
  return geometry.surface(columns, lines, {
    margin = windows.margin or configured.margin,
    gap = windows.gap or configured.gap,
  })
end

function M.workspace_widths(weights, columns)
  return geometry.workspace_widths(weights, columns)
end

function M.validate_surface(surface, expected)
  if not surface or not expected then
    return false
  end
  local list = surface.panes and surface.panes.list
  local preview = surface.panes and surface.panes.preview
  if not list or not preview then
    return false
  end
  local list_config = vim.api.nvim_win_get_config(list.window)
  local preview_config = vim.api.nvim_win_get_config(preview.window)
  return list_config.width == expected.left_width
    and preview_config.width == expected.right_width
    and list_config.height == expected.height
    and preview_config.height == expected.height
    and math.floor(list_config.row) == expected.row
    and math.floor(preview_config.row) == expected.row
    and math.floor(preview_config.col) == expected.right_col
    and preview_config.col - (list_config.col + list_config.width) == expected.gap
end

function M.validate_workspace(workspace, expected_widths)
  if not workspace or not workspace.order or #workspace.order == 0 then
    return false
  end
  for index, pane_name in ipairs(workspace.order) do
    local pane = workspace.panes[pane_name]
    if not pane or not vim.api.nvim_win_is_valid(pane.window) then
      return false
    end
    if index < #workspace.order and vim.api.nvim_win_get_width(pane.window) ~= expected_widths[index] then
      return false
    end
  end
  return true
end

function M.resize_surface(surface)
  return type(surface) == "table" and surface.resize and surface.resize() == true
end

function M.resize_workspace(workspace)
  if not workspace or not workspace.options or not workspace.options.render then
    return false
  end
  ui.resize_workspace(workspace)
  workspace.options.render(workspace)
  return true
end

return M
