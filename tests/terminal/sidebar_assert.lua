local mode = vim.env.PROUD_SIDEBAR_MODE or "initial"
local session = require("proud.session")
local state = session.current and session.current.state
local workspace = state and state.workspace
local sidebar = workspace and workspace.panes and workspace.panes.sidebar
local ok = sidebar ~= nil

if sidebar then
  local lines = vim.api.nvim_buf_get_lines(sidebar.buffer, 0, -1, false)
  local text = table.concat(lines, "\n")
  local width = vim.api.nvim_win_get_width(sidebar.window)
  ok = ok and #workspace.order == 2 and workspace.order[1] == "sidebar" and workspace.order[2] == "details"
  for _, line in ipairs(lines) do
    ok = ok and vim.fn.strdisplaywidth(line) == width
  end
  local tree = require("proud.components.tree")
  local files = tree.find(state.sidebar, "files")
  local commits = tree.find(state.sidebar, "commits")
  local checks = tree.find(state.sidebar, "checks")
  local function header(node)
    return node and table.concat(vim.tbl_map(function(section)
      return section.text or ""
    end, node.sections), " ") or ""
  end
  local expected_files_status = mode == "viewed"
      and "Files 5 · 2 of 5 viewed"
      or "Files 5 · 1 of 5 viewed"
  ok = ok and header(files) == expected_files_status
  ok = ok and header(commits) == "Commits 6"
  ok = ok and header(checks) == "Checks 4 of 5 passing"
  ok = ok and text:find("Files", 1, true) ~= nil
  ok = ok and text:find("Commits", 1, true) ~= nil
  ok = ok and text:find("Checks", 1, true) ~= nil
  ok = ok and text:find("✓ lint                 18s", 1, true) ~= nil
  ok = ok and text:find("✗ e2e / robot-studio   6m 40s", 1, true) ~= nil
  if mode == "initial" or mode == "expanded" then
    ok = ok and text:find("a3f91c2", 1, true) ~= nil
    ok = ok and text:find("+48", 1, true) ~= nil
  elseif mode == "movedown" then
    local selected = require("proud.components.tree").selected(state.sidebar)
    ok = ok and selected ~= nil and selected.label == "runTask.ts"
  elseif mode == "moveup" then
    local selected = require("proud.components.tree").selected(state.sidebar)
    ok = ok and selected ~= nil and selected.label == "retry.ts"
  elseif mode == "branch" then
    local selected = require("proud.components.tree").selected(state.sidebar)
    ok = ok and selected ~= nil and selected.id == "commits"
  elseif mode == "nativebranch" then
    local selected = require("proud.components.tree").selected(state.sidebar)
    ok = ok and selected ~= nil and selected.id == "commits"
  elseif mode == "collapsed" then
    ok = ok and text:find("a3f91c2", 1, true) == nil
    ok = ok and text:find("+48", 1, true) ~= nil
  elseif mode == "viewed" then
    ok = ok and text:find("retry.ts", 1, true) ~= nil
    local selected = require("proud.components.tree").selected(state.sidebar)
    local section_text = selected and table.concat(vim.tbl_map(function(section)
      return section.text or ""
    end, selected.sections), "\n") or ""
    ok = ok and section_text:find("viewed", 1, true) ~= nil
  end
end

if ok then
  vim.api.nvim_echo({ { ("SIDEBAR_%s_OK=true"):format(mode:upper()) } }, false, {})
else
  local selected = state and state.sidebar and require("proud.components.tree").selected(state.sidebar)
  vim.api.nvim_echo({
    { ("SIDEBAR_%s_OK=false selected=%s viewed=%s"):format(
      mode:upper(),
      selected and selected.id or "nil",
      state and state.files and state.files[1] and tostring(state.files[1].viewed) or "nil"
    ) },
  }, false, {})
end
