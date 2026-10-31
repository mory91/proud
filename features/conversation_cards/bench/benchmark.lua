local feature = require("proud.loader").load("conversation_cards")

local items = {}
for index = 1, 100 do
  table.insert(items, {
    id = "card-" .. index,
    depth = index % 3,
    author = "reviewer-" .. index,
    age = (index % 60) .. "m",
    meta_segments = {
      { text = "  reviewed", group = "ProudMuted" },
      { text = "  change requested", group = "ProudWarning" },
    },
    body = ("Review note %d for retry behavior and bounded delay handling."):format(index),
  })
end

return {
  options = {
    name = "conversation_cards.layout_100_native_cards",
    iterations = 30,
    warmup = 5,
  },
  sla = {
    p95_ms = 2,
    max_memory_kb = 512,
  },
  run = function()
    return feature.layout(items, { width = 100, margin = 0, start_row = 4 }).total_rows
  end,
}
