local feature = require("proud.loader").load("ui_resize")
local ui = require("proud.ui")
local state = {}
for row = 1, 100 do
  state[row] = ("responsive row %03d"):format(row)
end

return {
  options = {
    name = "ui_resize.relayout_100_rows",
    iterations = 30,
    warmup = 5,
  },
  sla = {
    p95_ms = 4,
    max_memory_kb = 512,
  },
  run = function()
    local geometry = feature.surface_geometry(160, 45)
    return ui.fit_view({ lines = state }, geometry.left_width)
  end,
}
