-- Pure layout calculations shared by the renderer (proud.ui) and the
-- ui_resize feature, so the drawn layout and its validation cannot drift.
local M = {}

-- Narrow terminals shrink the pane gap to at most one column.
M.narrow_width = 48
M.min_pane_width = 8

local function editor_chrome()
  local top = (vim.o.showtabline == 2 or (vim.o.showtabline == 1 and vim.fn.tabpagenr("$") > 1)) and 1 or 0
  local bottom = vim.o.cmdheight + (vim.o.laststatus > 0 and 1 or 0)
  return top, bottom
end

-- Geometry of the rounded two-pane surface.
-- `layout` is { margin = { top, bottom, left, right }, gap = n }.
function M.surface(columns, lines, layout)
  columns = math.max(1, math.floor(columns or vim.o.columns or 1))
  lines = math.max(1, math.floor(lines or vim.o.lines or 1))
  local margin = vim.deepcopy(layout.margin)
  local top, bottom = editor_chrome()
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
  local gap = layout.gap
  if available_width < M.narrow_width then
    gap = math.min(gap, 1)
  end
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

-- Column widths for native vertical-split workspaces, one per weight.
-- Separators take one column between panes; each pane is at least 8 wide.
function M.workspace_widths(weights, columns)
  weights = weights or { 1 }
  columns = math.max(1, math.floor(columns or vim.o.columns or 1))
  local pane_count = math.max(1, #weights)
  local available = math.max(pane_count * M.min_pane_width, columns - math.max(0, pane_count - 1))
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
    width = math.max(M.min_pane_width, width)
    widths[index] = width
    assigned = assigned + width
  end
  return widths
end

return M
