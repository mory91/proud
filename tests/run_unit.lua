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
  "single_diff_threads",
  "branch_compare",
  "keymap_help",
  "review_submission",
  "ui_resize",
}
for _, feature in ipairs(features) do
  local path = root .. "/features/" .. feature .. "/tests/unit_spec.lua"
  local chunk = assert(loadfile(path))
  chunk()(harness)
end
dofile(root .. "/tests/ui_theme_spec.lua")(harness)
dofile(root .. "/tests/ui_float_spec.lua")(harness)
dofile(root .. "/tests/ui_window_spec.lua")(harness)
dofile(root .. "/tests/ui_text_spec.lua")(harness)
dofile(root .. "/tests/ui_cursor_spec.lua")(harness)
dofile(root .. "/tests/unit_core_spec.lua")(harness)
harness.finish()
