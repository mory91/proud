local feature = require("proud.loader").load("review_submission")

local body = {}
for index = 1, 500 do
  table.insert(body, ("Review body line %d with deterministic content for the composer benchmark."):format(index))
end
local state = feature.create({ number = 482 }, {
  event = "REQUEST_CHANGES",
  body = body,
})

return {
  options = {
    name = "review_submission.render_500_line_body",
    iterations = 30,
    warmup = 5,
  },
  sla = {
    p95_ms = 2,
    max_memory_kb = 256,
  },
  run = function()
    return feature.render_panes(state, { decisions_width = 42 }).decisions.lines
  end,
}
