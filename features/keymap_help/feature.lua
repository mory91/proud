local ui = require("proud.ui")
local keymap = require("proud.keymap")

local M = {}

function M.create(groups, options)
  return {
    groups = vim.deepcopy(groups or keymap.help_groups()),
    options = options or {},
  }
end

function M.render(state)
  local lines = {
    "Proud help   bindings shown here are configurable",
    string.rep("─", 112),
  }
  local highlights = {}
  for _, group in ipairs(state.groups) do
    table.insert(lines, group.title)
    table.insert(highlights, { line = #lines - 1, start_col = 0, end_col = #group.title, group = "ProudAccentText" })
    table.insert(lines, "")
    for _, item in ipairs(group.items) do
      table.insert(lines, ("%-18s %s"):format(item.lhs, item.description))
      table.insert(highlights, { line = #lines - 1, start_col = 0, end_col = #item.lhs, group = "ProudBright" })
    end
    table.insert(lines, "")
  end
  table.insert(lines, "Commands")
  table.insert(lines, ":Proud prs                 list pull requests")
  table.insert(lines, ":Proud open {number}       open description and conversation")
  table.insert(lines, ":Proud diff {number}       open full-file inline diff")
  table.insert(lines, ":Proud compare {base} {head}")
  table.insert(lines, "")
  table.insert(lines, "GitHub auth validates and reuses a token; compare stays offline.")
  ui.view.span(lines, highlights, #lines - 7, "Commands", "ProudAccentText")
  ui.view.span(lines, highlights, #lines - 6, ":Proud prs", "ProudBright")
  ui.view.span(lines, highlights, #lines - 5, ":Proud open {number}", "ProudBright")
  ui.view.span(lines, highlights, #lines - 4, ":Proud diff {number}", "ProudBright")
  ui.view.span(lines, highlights, #lines - 3, ":Proud compare {base} {head}", "ProudBright")
  ui.view.span(lines, highlights, #lines - 1, "GitHub auth", "ProudAccentText")
  ui.view.span(lines, highlights, #lines - 1, "validates and reuses a token", "ProudAccentText")
  return { lines = lines, highlights = highlights }
end

function M.render_panes(state)
  local bindings = {
    lines = {
      "Proud help   current bindings",
      string.rep("─", 72),
    },
    highlights = {},
  }
  for _, group in ipairs(state.groups) do
    table.insert(bindings.lines, group.title)
    table.insert(bindings.highlights, {
      line = #bindings.lines - 1,
      start_col = 0,
      end_col = #group.title,
      group = "ProudAccentText",
    })
    table.insert(bindings.lines, "")
    for _, item in ipairs(group.items) do
      table.insert(bindings.lines, ("%-18s %s"):format(item.lhs, item.description))
      local line = #bindings.lines - 1
      ui.view.span(bindings.lines, bindings.highlights, line, item.lhs, "ProudBright")
      ui.view.span(bindings.lines, bindings.highlights, line, item.description, "ProudMuted")
    end
    table.insert(bindings.lines, "")
  end
  local commands = {
    lines = {
      "Commands",
      ":Proud prs                 list pull requests",
      ":Proud open {number}       description and conversation",
      ":Proud diff {number}       full-file inline diff",
      ":Proud compare {base} {head}",
    },
    highlights = {},
  }
  ui.view.span(commands.lines, commands.highlights, 0, "Commands", "ProudAccentText")
  ui.view.span(commands.lines, commands.highlights, 1, ":Proud prs", "ProudBright")
  ui.view.span(commands.lines, commands.highlights, 1, "list pull requests", "ProudMuted")
  ui.view.span(commands.lines, commands.highlights, 2, ":Proud open {number}", "ProudBright")
  ui.view.span(commands.lines, commands.highlights, 2, "description and conversation", "ProudMuted")
  ui.view.span(commands.lines, commands.highlights, 3, ":Proud diff {number}", "ProudBright")
  ui.view.span(commands.lines, commands.highlights, 3, "full-file inline diff", "ProudMuted")
  ui.view.span(commands.lines, commands.highlights, 4, ":Proud compare {base} {head}", "ProudBright")
  local runtime = {
    lines = {
      "Runtime",
      "GitHub auth validates and reuses a token.",
      "Compare works offline from local git.",
      "",
      "Every scene owns independent panes.",
      "Word motions stay inside the active pane.",
    },
    highlights = {},
  }
  ui.view.span(runtime.lines, runtime.highlights, 0, "Runtime", "ProudAccentText")
  ui.view.span(runtime.lines, runtime.highlights, 1, "GitHub auth", "ProudAccentText")
  ui.view.span(runtime.lines, runtime.highlights, 1, "validates and reuses a token", "ProudMuted")
  ui.view.span(runtime.lines, runtime.highlights, 2, "Compare", "ProudSuccessText")
  ui.view.span(runtime.lines, runtime.highlights, 2, "offline", "ProudMuted")
  ui.view.span(runtime.lines, runtime.highlights, 4, "independent panes.", "ProudSuccessText")
  ui.view.span(runtime.lines, runtime.highlights, 5, "Word motions", "ProudMuted")
  return { bindings = bindings, commands = commands, runtime = runtime }
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
