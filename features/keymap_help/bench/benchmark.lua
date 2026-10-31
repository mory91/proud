local feature = require("proud.loader").load("keymap_help")

local groups = {}
for group_index = 1, 20 do
  local items = {}
  for item_index = 1, 4 do
    table.insert(items, {
      lhs = "<leader>g" .. group_index .. item_index,
      description = "Deterministic mapping " .. group_index .. "-" .. item_index,
    })
  end
  table.insert(groups, {
    title = "Mapping group " .. group_index,
    items = items,
  })
end
local state = feature.create(groups)

return {
  options = {
    name = "keymap_help.render_80_mappings",
    iterations = 50,
    warmup = 10,
  },
  sla = {
    p95_ms = 1,
    max_memory_kb = 128,
  },
  run = function()
    return feature.render(state).lines
  end,
}
