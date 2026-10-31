local ui = require("proud.ui")

local M = {}

function M.surface_geometry(columns, lines, options)
  options = options or {}
  columns = math.max(1, math.floor(columns or vim.o.columns or 1))
  lines = math.max(1, math.floor(lines or vim.o.lines or 1))
  local margin = vim.deepcopy((options.windows and options.windows.margin) or ui.layout_config().margin)
  local gap = (options.windows and options.windows.gap) or ui.layout_config().gap
  local top = (vim.o.showtabline == 2 or (vim.o.showtabline == 1 and vim.fn.tabpagenr("$") > 1)) and 1 or 0
  local bottom = vim.o.cmdheight + (vim.o.laststatus > 0 and 1 or 0)
  local editor_height = math.max(3, lines - top - bottom)
  local outer_height = editor_height - margin.top - margin.bottom
  if outer_height < 3 then
    local overflow = 3 - outer_height
    local top_reduction = math.min(margin.top, math.ceil(overflow / 2))
    margin.top = margin.top - top_reduction
    margin.bottom = math.max(0, margin.bottom - (overflow - top_reduction))
    outer_height = 3
  end
  local available_width = math.max(2, columns - margin.left - margin.right)
  gap = math.min(gap, math.max(0, available_width - 2))
  local left_width = math.max(1, math.floor((available_width - gap) / 2))
  local right_width = math.max(1, available_width - gap - left_width)
  return {
    columns = columns,
    lines = lines,
    top = top,
    bottom = bottom,
    row = top + margin.top + 1,
    left_col = margin.left,
    right_col = margin.left + left_width + gap,
    left_width = left_width,
    right_width = right_width,
    height = outer_height - 2,
    gap = gap,
    available_width = left_width + gap + right_width,
  }
end

function M.workspace_widths(weights, columns)
  weights = weights or { 1 }
  columns = math.max(1, math.floor(columns or vim.o.columns or 1))
  local pane_count = math.max(1, #weights)
  local available = math.max(pane_count * 8, columns - math.max(0, pane_count - 1))
  local total_weight = 0
  for _, weight in ipairs(weights) do
    total_weight = total_weight + math.max(0.01, tonumber(weight) or 1)
  end
  local widths = {}
  local assigned = 0
  for index, weight in ipairs(weights) do
    local width = index == pane_count
      and available - assigned
      or math.floor(available * math.max(0.01, tonumber(weight) or 1) / total_weight)
    width = math.max(8, width)
    widths[index] = width
    assigned = assigned + width
  end
  return widths
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
