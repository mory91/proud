local feature = require("proud.loader").load("branch_compare")

local commits = {}
for index = 1, 100 do
  table.insert(commits, {
    sha = ("%07x"):format(index * 7919),
    message = "Commit " .. index .. " improves deterministic compare rendering",
  })
end
local files = {}
for index = 1, 500 do
  table.insert(files, {
    path = ("packages/module%02d/src/file%03d.ts"):format(index % 30, index),
    status = index % 5 == 0 and "A" or "M",
    additions = index % 120,
    deletions = index % 44,
    notes = index % 10,
  })
end
local state = feature.create({
  base = "main",
  head = "feat/compare",
  ahead = 120,
  behind = 30,
  commits = commits,
  files = files,
  notes = 12,
})

return {
  options = {
    name = "branch_compare.render_100_commits_500_files",
    iterations = 25,
    warmup = 5,
  },
  sla = {
    p95_ms = 3,
    max_memory_kb = 512,
  },
  run = function()
    return feature.render(state).lines
  end,
}
