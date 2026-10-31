local github = require("proud.loader").load("github_api")

local files = {}
for index = 1, 2000 do
  table.insert(files, {
    filename = ("src/module%02d/file%04d.ts"):format(index % 40, index),
    status = index % 5 == 0 and "ADDED" or "MODIFIED",
    patch = ("@@ -%d,%d +%d,%d @@\n-old%d\n+new%d\n"):format(index, 2, index, 2, index, index),
  })
end

return {
  options = {
    name = "github_api.patch_from_2000_file_payloads",
    iterations = 30,
    warmup = 5,
  },
  sla = {
    p95_ms = 4,
    max_memory_kb = 768,
  },
  run = function()
    return github.build_patch_from_files(files)
  end,
}
