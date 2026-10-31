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

-- Returns a new layout: `base` with any valid values from `options`
-- (either { windows = {...} } or the windows table itself) applied.
-- Neither argument is modified.
function M.resolve(options, base)
  options = options or {}
  base = base or layout
  local windows = options.windows or options
  local margin = windows.margin or {}
  return {
    margin = {
      top = nonnegative_integer(margin.top, base.margin.top),
      bottom = nonnegative_integer(margin.bottom, base.margin.bottom),
      left = nonnegative_integer(margin.left, base.margin.left),
      right = nonnegative_integer(margin.right, base.margin.right),
    },
    gap = nonnegative_integer(windows.gap, base.gap),
  }
end

-- Sets the global default layout (called from setup()).
function M.configure(options)
  layout = M.resolve(options)
  return M.layout_config()
end

function M.layout_config()
  return vim.deepcopy(layout)
end

return M
