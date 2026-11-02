local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
local features = {
  "github_api",
  "github_credentials",
  "conversation_cards",
  "sidebar",
  "pull_request_browser",
  "pull_request_overview",
  "diff_view",
  "branch_compare",
  "keymap_help",
  "review_submission",
  "ui_resize",
}

local failed = false
for _, feature in ipairs(features) do
  local benchmark = assert(loadfile(root .. "/features/" .. feature .. "/bench/benchmark.lua"))()
  local workloads = benchmark.workloads or { benchmark }
  for index = 1, #workloads do
    local completed = vim.system({
      vim.v.progpath,
      "--headless",
      "-u",
      root .. "/tests/minimal_init.lua",
      "-l",
      root .. "/bench/run_workload.lua",
      feature,
      tostring(index),
    }, {
      cwd = root,
      text = true,
    }):wait()
    local output = completed.stdout
    if not output or output == "" then
      output = completed.stderr
    end
    if output and output ~= "" then
      local cleaned = output:gsub("\n+$", "")
      print(cleaned)
    end
    if completed.code ~= 0 then
      failed = true
    end
  end
end
os.exit(failed and 1 or 0)
