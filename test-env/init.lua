local root = vim.env.PROUD_PLUGIN_ROOT
assert(root and root ~= "", "PROUD_PLUGIN_ROOT is required")

vim.opt.runtimepath:prepend(root)
vim.opt.loadplugins = false
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  package.path,
}, ";")

local keymaps = {}
if vim.env.PROUD_TEST_NEXT_ITEM then
  keymaps.next_item = vim.env.PROUD_TEST_NEXT_ITEM
end
if vim.env.PROUD_TEST_PREVIOUS_ITEM then
  keymaps.previous_item = vim.env.PROUD_TEST_PREVIOUS_ITEM
end

require("proud").setup({
  provider = {
    kind = "github",
    cwd = vim.env.PROUD_GIT_REPO,
    repository = vim.env.PROUD_GITHUB_REPOSITORY,
    base_url = vim.env.PROUD_GITHUB_API_URL,
    token = vim.env.PROUD_GITHUB_TOKEN or vim.env.GITHUB_TOKEN,
    token_file = vim.env.PROUD_GITHUB_TOKEN_FILE,
    cache_items = 128,
  },
  keymaps = keymaps,
})

local start = vim.env.PROUD_START or "prs"
vim.schedule(function()
  if start == "prs" then
    require("proud.session").open_pull_requests({
      query = vim.env.PROUD_PR_QUERY or "",
    })
  elseif start == "demo" then
    require("proud.session").demo(vim.env.PROUD_DEMO_SCREEN)
  elseif start == "help" then
    require("proud.session").open_help()
  elseif start == "overview" then
    local number = assert(tonumber(vim.env.PROUD_PR_NUMBER), "PROUD_PR_NUMBER must be set")
    require("proud.session").open_overview(number)
  elseif start == "diff" then
    local number = assert(tonumber(vim.env.PROUD_PR_NUMBER), "PROUD_PR_NUMBER must be set")
    require("proud.session").open_diff(number, vim.env.PROUD_DIFF_PATH)
  elseif start == "compare" then
    local base = assert(vim.env.PROUD_COMPARE_BASE, "PROUD_COMPARE_BASE must be set")
    local head = assert(vim.env.PROUD_COMPARE_HEAD, "PROUD_COMPARE_HEAD must be set")
    require("proud.session").open_compare(base, head)
  elseif start == "github-sdk-e2e" then
    dofile(root .. "/tests/github_sdk_terminal_spec.lua")
  elseif start == "thread-counts-e2e" then
    dofile(root .. "/tests/thread_counts_terminal_spec.lua")
  elseif start == "relative-time-e2e" then
    dofile(root .. "/tests/relative_time_terminal_spec.lua")
  elseif start == "metadata-e2e" then
    dofile(root .. "/tests/preview_metadata_terminal_spec.lua")
  elseif start == "lazy-pagination-e2e" then
    dofile(root .. "/tests/lazy_pagination_terminal_spec.lua")
  elseif start == "ui-first-e2e" then
    dofile(root .. "/tests/ui_first_terminal_spec.lua")
  elseif start == "credentials-e2e" then
    dofile(root .. "/tests/github_credentials_terminal_spec.lua")
  elseif start == "credentials-reuse-e2e" then
    dofile(root .. "/tests/github_credentials_reuse_terminal_spec.lua")
  elseif start ~= "none" then
    error("Unknown PROUD_START: " .. start)
  end
end)
