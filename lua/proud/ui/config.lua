local M = {}

local layout = {
  margin = { top = 3, bottom = 2, left = 2, right = 2 },
  gap = 3,
}

local function nonnegative_integer(value, fallback)
  value = tonumber(value)
  if not value or value < 0 then
    return fallback
  end
  return math.floor(value)
end

function M.configure(options)
  options = options or {}
  local windows = options.windows or options
  local margin = windows.margin or {}
  layout.margin.top = nonnegative_integer(margin.top, layout.margin.top)
  layout.margin.bottom = nonnegative_integer(margin.bottom, layout.margin.bottom)
  layout.margin.left = nonnegative_integer(margin.left, layout.margin.left)
  layout.margin.right = nonnegative_integer(margin.right, layout.margin.right)
  layout.gap = nonnegative_integer(windows.gap, layout.gap)
  return M.layout_config()
end

function M.layout_config()
  return vim.deepcopy(layout)
end

return M
