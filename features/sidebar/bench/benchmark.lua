local feature = require("proud.loader").load("sidebar")

local files = {}
for index = 1, 450 do
  table.insert(files, {
    path = ("packages/module%02d/src/file%03d.ts"):format(index % 25, index),
    additions = index % 90,
    deletions = index % 40,
    threads = index % 4,
    viewed = index % 5 == 0,
  })
end
local checks = {}
for index = 1, 50 do
  table.insert(checks, {
    name = ("check-%03d / integration"):format(index),
    status = index % 5 == 0 and "fail" or "pass",
    duration = ("%dm %02ds"):format(index % 10, index % 60),
  })
end
local nodes = feature.overview_nodes({
  files = files,
  commits = {},
  checks = checks,
})
local state = feature.create(nodes)
local move_state = feature.create(nodes)

local render_workload = {
  options = {
    name = "sidebar.render_500_nodes",
    iterations = 30,
    warmup = 5,
  },
  sla = {
    p95_ms = 2,
    max_memory_kb = 256,
  },
  run = function()
    return feature.render(state, 48).lines
  end,
}

local move_buffer = vim.api.nvim_create_buf(false, true)
local move_window = vim.api.nvim_open_win(move_buffer, false, {
  relative = "editor",
  row = 1,
  col = 1,
  width = 48,
  height = 20,
  style = "minimal",
})
local move_options = {
  window = move_window,
  width = 48,
  on_change = function(kind)
    assert(kind == "selection", "selection changes use the selection callback")
  end,
}
feature.attach(move_buffer, move_state, move_options)
local move_workload = {
  options = {
    name = "sidebar.move_500_nodes",
    iterations = 200,
    warmup = 20,
  },
  sla = {
    p95_ms = 0.5,
    max_memory_kb = 64,
  },
  run = function()
    if move_state.move(1) then
      return 1
    end
    move_state.move(-1)
    return 0
  end,
}

return {
  workloads = {
    render_workload,
    move_workload,
  },
}
