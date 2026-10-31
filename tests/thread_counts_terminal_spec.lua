local provider = require("proud.provider")
local feature = require("proud.loader").load("pull_request_browser")

local pulls = {}
for index, count in ipairs({ 3, 1, 0 }) do
  table.insert(pulls, provider.normalize_pull_request({
    number = 900 + index,
    title = "Terminal review thread count " .. index,
    author = { login = "api-author-" .. index },
    age = "2h",
    additions = 77,
    deletions = 9,
    reviewDecision = "REVIEW_REQUIRED",
    labels = { nodes = { { name = "api" } } },
    reviewThreads = { totalCount = count },
  }))
end

local state = feature.create(pulls, { query = "" })
feature.open(state, {
  on_open = function() end,
})
vim.api.nvim_echo({ { "THREAD_COUNTS_TERMINAL_READY=true" } }, false, {})
