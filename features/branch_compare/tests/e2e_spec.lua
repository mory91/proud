return function(test)
  local feature = require("proud.loader").load("branch_compare")
  local fixtures = require("proud.fixtures")
  local state = feature.create(fixtures.compare)
  local buffer = feature.open(state)
  vim.api.nvim_feedkeys("S", "x", false)
  test.eq("feat/monitor-diffs", state.base)
  test.eq("main", state.head)
  test.eq(2, #state.workspace.order, "compare uses summary and changes panes")
  test.truthy(state.workspace.panes.summary.buffer ~= state.workspace.panes.changes.buffer)
  vim.cmd("silent! tabclose!")

  local session = require("proud.session")
  session.configure({ cwd = vim.fn.getcwd() })
  session.open_compare("missing-base", "missing-head")
  test.truthy(session.current and session.current.feature == "branch_compare", "comparison scene opens before git commands resolve")
  local changes_buffer = session.current.state.workspace.panes.changes.buffer
  test.contains(
    table.concat(vim.api.nvim_buf_get_lines(changes_buffer, 0, -1, false), "\n"),
    "Loading comparison...",
    "comparison placeholder UI is visible while git is working"
  )
  vim.cmd("silent! tabclose!")
end
