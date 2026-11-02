-- Thread window text for a long conversation: 50 comments with
-- multi-paragraph bodies (about 400 characters each), wrapped to the
-- 84-cell window, with the reply header. This runs when the window opens
-- and after every reply or resolve.
local feature = require("proud.loader").load("thread_window")

local paragraph = "Deterministic review comment text that is long enough to wrap several times inside the thread window, with `code` and a link https://example.com/pull/482#discussion_r1."
local comments = {}
for index = 1, 50 do
  comments[index] = {
    author = "reviewer-" .. (index % 5),
    age = index .. "h ago",
    body = paragraph .. "\n\n" .. paragraph,
    pending = index % 10 == 0 or nil,
  }
end
local threads = { {
  path = "packages/runner/src/task/retry.ts",
  line = 14,
  resolved = false,
  comments = comments,
} }
local options = {
  author = "reviewer-1",
  code = "      const delay = baseDelayMs * 2 ** attempt",
  replying = threads[1],
  viewer = "morteza",
}

return {
  options = {
    name = "thread_window.view_50_comments",
    iterations = 25,
    warmup = 3,
  },
  sla = {
    p95_ms = 2,
    max_memory_kb = 512,
  },
  run = function()
    local view = feature.view(threads, 84, options)
    return #view.lines
  end,
}
