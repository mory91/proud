local feature = require("proud.loader").load("pull_request_overview")

local files = {}
for index = 1, 200 do
  table.insert(files, {
    path = ("packages/module%02d/src/file%03d.ts"):format(index % 20, index),
    status = index % 4 == 0 and "A" or "M",
    additions = index % 80,
    deletions = index % 31,
    threads = index % 5,
    viewed = index % 3 == 0,
  })
end
local body = {}
for index = 1, 250 do
  table.insert(body, "Description line " .. index .. " for deterministic performance verification.")
end
local state = feature.create({
  number = 482,
  title = "Add retry backoff to robot task runner",
  author = "sara-k",
  state = "Open",
  head_ref = "feat/task-retry-backoff",
  base_ref = "main",
  labels = { "runner", "reliability" },
  body = body,
  files = files,
  commits = {},
  checks = {
    { name = "unit", status = "pass", duration = "1s" },
    { name = "e2e", status = "fail", duration = "2s" },
  },
})

return {
  options = {
    name = "pull_request_overview.render_200_files_250_body_lines",
    iterations = 30,
    warmup = 5,
  },
  sla = {
    p95_ms = 4,
    max_memory_kb = 768,
  },
  run = function()
    local panes = feature.render_panes(state, { sidebar_width = 44 })
    return vim.list_extend(vim.deepcopy(panes.sidebar.lines), panes.details.lines)
  end,
}
