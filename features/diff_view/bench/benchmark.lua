-- Live diff work for one file: diff a 1,200-line buffer against its merge
-- base (600 changed lines: 600 highlighted, 600 deleted virtual lines) and
-- draw the decorations, color the deleted lines in view with the base
-- text's treesitter syntax (cold: no cached captures or rows), then place
-- 1,000 thread signs with end-of-line previews. This is what runs when a
-- file opens (the base is parsed asynchronously beforehand, off this
-- path), and the diff part runs again on every edit.
local feature = require("proud.loader").load("diff_view")
local inline = require("proud.ui.inline_diff")

local head, base = {}, {}
for index = 1, 1200 do
  head[index] = ("local value%d = compute(%d) -- line %d"):format(index, index, index)
  base[index] = index % 2 == 0 and ('local value%d = legacy(%d, "old")'):format(index, index) or head[index]
end
local base_text = table.concat(base, "\n") .. "\n"

local threads = {}
for index = 1, 1000 do
  local comments = {}
  for comment_index = 1, 3 do
    comments[comment_index] = {
      author = "reviewer-" .. comment_index,
      age = comment_index .. "h ago",
      body = "Deterministic review comment " .. comment_index .. " for thread " .. index,
    }
  end
  threads[index] = { path = "large.ts", line = index, resolved = index % 4 == 0, comments = comments }
end

local buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, head)
vim.api.nvim_win_set_buf(0, buffer)
local syntax = assert(inline.syntax(base_text, "lua"), "the lua parser is bundled with Neovim")
inline.parse(syntax, nil, true)
local state = feature.create({ threads = threads })
state.source = { kind = "worktree", base = "HEAD" }
local file = { path = "large.ts", status = "M" }

return {
  options = {
    name = "diff_view.live_diff_1200_lines_1000_threads",
    iterations = 15,
    warmup = 3,
  },
  sla = {
    p95_ms = 8,
    max_memory_kb = 2048,
  },
  run = function()
    syntax.captures, syntax.rows = {}, {}
    local stats, marks = inline.decorate(buffer, base_text, base, 8, syntax)
    assert(inline.color(buffer, base, syntax, marks) > 0, "deleted lines in view are colored")
    feature.place_threads(state, buffer, file)
    return stats.added + stats.deleted
  end,
}
