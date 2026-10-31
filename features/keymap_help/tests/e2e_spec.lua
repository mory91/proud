return function(test)
  local feature = require("proud.loader").load("keymap_help")
  local keymap = require("proud.keymap")
  keymap.setup({ help = "<F2>", quit = "<F4>" })
  local state = feature.create()
  test.truthy(feature.toggle(state))
  test.truthy(vim.api.nvim_win_is_valid(state.window))
  local bindings = state.workspace.panes.bindings
  local rule = vim.api.nvim_buf_get_lines(bindings.buffer, 1, 2, false)[1] or ""
  test.eq(vim.api.nvim_win_get_width(bindings.window), vim.fn.strdisplaywidth(rule), "the help rule spans the bindings pane")
  test.eq(3, #state.workspace.order, "help uses bindings, commands, and runtime panes")
  test.truthy(state.workspace.panes.bindings.buffer ~= state.workspace.panes.commands.buffer)
  test.truthy(state.workspace.panes.commands.buffer ~= state.workspace.panes.runtime.buffer)
  test.truthy(not feature.toggle(state))
  test.truthy(state.window == nil)
  keymap.setup()
end
