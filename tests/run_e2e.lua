local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
local harness = dofile(root .. "/tests/harness.lua")
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
for _, feature in ipairs(features) do
  local path = root .. "/features/" .. feature .. "/tests/e2e_spec.lua"
  local chunk = assert(loadfile(path))
  chunk()(harness)
end
if vim.env.PROUD_SKIP_MEMORY_LEAKS ~= "1" and vim.env.PROUD_RUN_MEMORY_LEAKS == "1" then
  for _, feature in ipairs({
    "github_credentials",
    "conversation_cards",
    "sidebar",
    "pull_request_browser",
    "pull_request_overview",
    "diff_view",
    "branch_compare",
    "keymap_help",
    "review_submission",
  }) do
    local path = root .. "/features/" .. feature .. "/tests/memory_leak_spec.lua"
    local chunk = assert(loadfile(path))
    chunk()(harness)
  end
end
dofile(root .. "/tests/e2e_core_spec.lua")(harness)
harness.finish()
