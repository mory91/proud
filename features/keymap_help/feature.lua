local ui = require("proud.ui")
local keymap = require("proud.keymap")

local M = {}

function M.create(groups, options)
  return {
    groups = vim.deepcopy(groups or keymap.help_groups()),
    options = options or {},
  }
end

-- Byte padding, matching string.format's %-Ns columns.
local function pad(value, width)
  return string.rep(" ", math.max(0, width - #value))
end

local function render_groups(v, groups, describe_group)
  for _, group in ipairs(groups) do
    v:line({ group.title, "ProudAccentText" })
    v:blank()
    for _, item in ipairs(group.items) do
      v:line({ item.lhs, "ProudBright" }, pad(item.lhs, 18), " ", { item.description, describe_group })
    end
    v:blank()
  end
end

-- One command row: the command in bright text, then an optional muted note
-- starting at column 27.
local function command_line(v, command, note, note_group)
  if note then
    v:line({ command, "ProudBright" }, pad(command, 27), { note, note_group })
  else
    v:line({ command, "ProudBright" })
  end
end

function M.render(state)
  local v = ui.view.new()
  v:line("Proud help   bindings shown here are configurable")
  v:rule(nil, 112)
  render_groups(v, state.groups, nil)
  v:line({ "Commands", "ProudAccentText" })
  command_line(v, ":Proud prs", "list pull requests")
  command_line(v, ":Proud open {number}", "open description and conversation")
  command_line(v, ":Proud diff {number}", "open full-file inline diff")
  command_line(v, ":Proud compare {base} {head}")
  v:blank()
  v:line(
    { "GitHub auth", "ProudAccentText" }, " ",
    { "validates and reuses a token", "ProudAccentText" }, "; compare stays offline."
  )
  return v:build()
end

function M.render_panes(state)
  local bindings = ui.view.new()
  bindings:line("Proud help   current bindings")
  bindings:rule(nil, 72)
  render_groups(bindings, state.groups, "ProudMuted")

  local commands = ui.view.new()
  commands:line({ "Commands", "ProudAccentText" })
  command_line(commands, ":Proud prs", "list pull requests", "ProudMuted")
  command_line(commands, ":Proud open {number}", "description and conversation", "ProudMuted")
  command_line(commands, ":Proud diff {number}", "full-file inline diff", "ProudMuted")
  command_line(commands, ":Proud compare {base} {head}")

  local runtime = ui.view.new()
  runtime:line({ "Runtime", "ProudAccentText" })
  runtime:line({ "GitHub auth", "ProudAccentText" }, " ", { "validates and reuses a token", "ProudMuted" }, ".")
  runtime:line({ "Compare", "ProudSuccessText" }, " works ", { "offline", "ProudMuted" }, " from local git.")
  runtime:blank()
  runtime:line("Every scene owns ", { "independent panes.", "ProudSuccessText" })
  runtime:line({ "Word motions", "ProudMuted" }, " stay inside the active pane.")

  return { bindings = bindings:build(), commands = commands:build(), runtime = runtime:build() }
end

function M.open(state, options)
  local panes = M.render_panes(state)
  local workspace = ui.open_workspace("proud://help", {
    { name = "bindings", buffer_name = "proud://help/bindings", title = "Proud help", view = panes.bindings, weight = 0.46 },
    { name = "commands", buffer_name = "proud://help/commands", title = "Proud help", view = panes.commands, weight = 0.32 },
    { name = "runtime", buffer_name = "proud://help/runtime", title = "Proud help", view = panes.runtime, weight = 0.22 },
  }, {
    focus = "bindings",
    title = "Proud help",
    statusline = "Proud help",
  })
  state.workspace = workspace
  state.buffer = ui.workspace_buffer(workspace, "bindings")
  state.window = ui.workspace_window(workspace, "bindings")
  return state.buffer, state.window
end

function M.attach(buffer, state, options)
  options = options or {}
  local close = function()
    local workspace = state.workspace
    if options.on_quit then
      options.on_quit()
    end
    ui.close_workspace(workspace)
    state.workspace = nil
    state.window = nil
    state.buffer = nil
  end
  keymap.map_workspace(state.workspace, "n", "quit", close, "Close help")
  keymap.map_workspace(state.workspace, "n", "help", options.on_toggle or close, "Toggle help")
end

function M.toggle(state)
  if state.workspace and vim.api.nvim_tabpage_is_valid(state.workspace.tabpage) then
    ui.close_workspace(state.workspace)
    state.workspace = nil
    state.window = nil
    state.buffer = nil
    return false
  end
  state.buffer, state.window = M.open(state)
  M.attach(state.buffer, state, {
    on_quit = function()
      state.workspace = nil
      state.window = nil
      state.buffer = nil
    end,
    on_toggle = function()
      M.toggle(state)
    end,
  })
  return true
end

return M
