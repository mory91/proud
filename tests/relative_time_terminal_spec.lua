local util = require("proud.util")
local provider = require("proud.provider")
local feature = require("proud.loader").load("pull_request_browser")

local now = assert(util.parse_iso8601("2026-10-15T12:00:00Z"))
local pulls = {}
for index, created_at in ipairs({
  "2026-10-15T11:36:00Z",
  "2026-10-15T11:00:00Z",
  "2026-10-14T12:00:00Z",
}) do
  table.insert(pulls, provider.normalize_pull_request({
    number = 920 + index,
    title = "Terminal relative timestamp " .. index,
    author = { login = "time-author-" .. index },
    createdAt = created_at,
    additions = 7,
    deletions = 2,
    reviewDecision = "REVIEW_REQUIRED",
    reviewThreads = { totalCount = 0 },
  }, { now = now }))
end

local state = feature.create(pulls, { query = "" })
feature.open(state, {
  on_open = function() end,
})
vim.api.nvim_echo({ { "RELATIVE_TIME_TERMINAL_READY=true" } }, false, {})
