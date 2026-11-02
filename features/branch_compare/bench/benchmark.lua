local feature = require("proud.loader").load("branch_compare")

local commits = {}
for index = 1, 100 do
  table.insert(commits, {
    sha = ("%040x"):format(index * 7919),
    short = ("%07x"):format(index * 7919),
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
-- The compare sidebar after git data arrives: Compare info, 100 commits
-- and 500 files, built as tree nodes and rendered (what every refresh does).
local tree = require("proud.components.tree")
local sidebar = require("proud.loader").load("sidebar")
local state = feature.create({ base = "main", head = "feat/compare" })
state.ahead, state.behind = 120, 30
state.base_short, state.head_short = "4c0e1aa", "9a7d3f0"
state.commits, state.files = commits, files
state.loading = false

state.sidebar = tree.create(feature.sidebar_nodes(state))

return {
  workloads = {
    -- What a refresh draws (resize, selection sync): the sidebar tree for
    -- 100 commits and 500 files, rendered. Same workload and SLA as the
    -- compare page's original render benchmark.
    {
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
        return sidebar.render(state.sidebar, 44).lines
      end,
    },
    -- When data changes (loading, picking a commit): the tree is rebuilt
    -- from git data, then rendered.
    {
      options = {
        name = "branch_compare.rebuild_100_commits_500_files",
        iterations = 25,
        warmup = 5,
      },
      sla = {
        p95_ms = 4,
        max_memory_kb = 3072,
      },
      run = function()
        return sidebar.render(tree.create(feature.sidebar_nodes(state)), 44).lines
      end,
    },
  },
}
