local feature = require("proud.loader").load("single_diff_threads")

local patch = {
  "diff --git a/large.ts b/large.ts",
  "--- a/large.ts",
  "+++ b/large.ts",
  "@@ -1,1000 +1,1000 @@",
}
for index = 1, 1000 do
  table.insert(patch, (index % 2 == 0 and "+const value%s = %s" or " const value%s = %s"):format(index, index))
end
local threads = {}
for index = 1, 1000 do
  local comments = {}
  for comment_index = 1, 3 do
    table.insert(comments, {
      author = "reviewer-" .. comment_index,
      age = comment_index .. "h ago",
      body = "Deterministic review comment " .. comment_index .. " for thread " .. index,
    })
  end
  table.insert(threads, {
    path = "large.ts",
    line = index,
    resolved = index % 4 == 0,
    comments = comments,
  })
end
local source = {}
for index = 1, 1200 do
  table.insert(source, (index % 2 == 0 and "const value%s = %s" or " const value%s = %s"):format(index, index))
end
local state = feature.create({ number = 482, head_ref = "feat/large" }, threads, table.concat(patch, "\n"), {
  ["large.ts"] = source,
})

return {
  options = {
    name = "single_diff_threads.render_1200_file_lines_1000_threads",
    iterations = 15,
    warmup = 3,
  },
  sla = {
    p95_ms = 8,
    max_memory_kb = 2048,
  },
  run = function()
    return feature.render(state).lines
  end,
}
