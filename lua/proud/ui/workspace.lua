local ui_geometry = require("proud.ui.geometry")
local ui_lifecycle = require("proud.ui.lifecycle")
local ui_render = require("proud.ui.render")
local ui_text_frame = require("proud.ui.text_frame")
local ui_window = require("proud.ui.window")

local M = {}

function M.open_workspace(name, panes, options)
  options = options or {}
  vim.cmd("tabnew")
  local tab_initial_buffer = vim.api.nvim_get_current_buf()
  local workspace = {
    name = name,
    tabpage = vim.api.nvim_get_current_tabpage(),
    panes = {},
    order = {},
    options = options,
    owned_buffers = { tab_initial_buffer },
  }
  local weights = {}
  for _, pane in ipairs(panes) do
    table.insert(weights, pane.weight or 1)
  end
  local widths = ui_geometry.workspace_widths(weights, vim.o.columns)
  workspace.widths = vim.deepcopy(widths)

  for index, pane in ipairs(panes) do
    local buffer_before = vim.api.nvim_get_current_buf()
    if index > 1 then
      vim.cmd("botright vnew")
      local split_buffer = vim.api.nvim_get_current_buf()
      if split_buffer ~= buffer_before then
        table.insert(workspace.owned_buffers, split_buffer)
      end
    end
    local window = vim.api.nvim_get_current_win()
    local buffer_name = pane.buffer_name or (name .. "/" .. pane.name)
    local buffer = ui_window.buffer(buffer_name)
    vim.api.nvim_win_set_buf(window, buffer)
    ui_window.decorate(window, buffer, buffer_name, {
      title = pane.title or options.title,
      statusline = options.statusline,
    })
    workspace.panes[pane.name] = {
      name = pane.name,
      buffer_name = buffer_name,
      buffer = buffer,
      window = window,
      title = pane.title,
      weight = pane.weight or 1,
      width = widths[index],
      -- Views are rebuilt on every render and never mutated, so keeping a
      -- reference is enough for re-rendering on resize. External panes
      -- (e.g. a diff pane showing real files) manage their own content.
      last_view = not pane.external and (pane.view or { lines = {} }) or nil,
    }
    table.insert(workspace.order, pane.name)
    table.insert(workspace.owned_buffers, buffer)
    if not pane.external then
      ui_render.render(buffer, pane.view or { lines = {} })
      ui_text_frame.sync(workspace.panes[pane.name], pane.view)
    end
  end

  for index = 1, #panes - 1 do
    local pane = workspace.panes[panes[index].name]
    pcall(vim.api.nvim_win_set_width, pane.window, widths[index])
  end
  local focus = options.focus or panes[1].name
  if workspace.panes[focus] then
    vim.api.nvim_set_current_win(workspace.panes[focus].window)
  end

  local user_on_close = options.on_close
  local lifecycle = ui_lifecycle.create_scene_lifecycle({
    tabpage = workspace.tabpage,
    on_close = function(scene)
      ui_text_frame.close_all(workspace)
      if user_on_close then
        pcall(user_on_close, scene)
      end
    end,
    on_closed = options.on_closed,
  })
  for _, buffer in ipairs(workspace.owned_buffers) do
    lifecycle.track_buffer(buffer)
  end
  for _, pane in pairs(workspace.panes) do
    lifecycle.track_window(pane.window)
  end
  workspace.lifecycle = lifecycle
  workspace.close = lifecycle.close
  vim.api.nvim_create_autocmd("VimResized", {
    group = lifecycle.group,
    callback = function()
      M.resize_workspace(workspace)
    end,
  })
  return workspace
end

local function visible_panes(workspace)
  local names = {}
  for _, pane_name in ipairs(workspace.order) do
    local pane = workspace.panes[pane_name]
    if not pane.hidden and pane.window and vim.api.nvim_win_is_valid(pane.window) then
      names[#names + 1] = pane_name
    end
  end
  return names
end

-- Applies weight-based widths to the visible panes.
local function apply_widths(workspace)
  local names = visible_panes(workspace)
  local weights = {}
  for _, pane_name in ipairs(names) do
    table.insert(weights, workspace.panes[pane_name].weight)
  end
  local widths = ui_geometry.workspace_widths(weights, vim.o.columns)
  workspace.widths = vim.deepcopy(widths)
  for index, pane_name in ipairs(names) do
    local pane = workspace.panes[pane_name]
    pane.width = widths[index]
    if index < #names then
      pcall(vim.api.nvim_win_set_width, pane.window, widths[index])
    end
  end
end

function M.resize_workspace(workspace)
  if not vim.api.nvim_tabpage_is_valid(workspace.tabpage) then
    return
  end
  apply_widths(workspace)
  for _, pane_name in ipairs(workspace.order) do
    local pane = workspace.panes[pane_name]
    if not pane.hidden and pane.last_view and vim.api.nvim_buf_is_valid(pane.buffer) then
      ui_render.render(pane.buffer, pane.last_view)
      ui_text_frame.sync(pane, pane.last_view)
    end
  end
  if workspace.options.on_resize then
    workspace.options.on_resize(workspace)
  end
end

function M.pane_visible(workspace, pane_name)
  local pane = workspace and workspace.panes[pane_name]
  return pane ~= nil and not pane.hidden and pane.window ~= nil and vim.api.nvim_win_is_valid(pane.window)
end

-- Hides a pane: closes its window but keeps its buffer and content. The
-- scene stays open; focus moves to the next visible pane when needed.
function M.hide_pane(workspace, pane_name)
  local pane = workspace.panes[pane_name]
  if not M.pane_visible(workspace, pane_name) or #visible_panes(workspace) < 2 then
    return false
  end
  local window = pane.window
  if vim.api.nvim_get_current_win() == window then
    for _, other in ipairs(visible_panes(workspace)) do
      if other ~= pane_name then
        vim.api.nvim_set_current_win(workspace.panes[other].window)
        break
      end
    end
  end
  ui_text_frame.close(pane.text_frame)
  pane.text_frame = nil
  workspace.lifecycle.untrack_window(window)
  pane.hidden = true
  pane.window = nil
  pcall(vim.api.nvim_win_close, window, true)
  apply_widths(workspace)
  if workspace.options.on_pane_toggled then
    workspace.options.on_pane_toggled(pane_name, false)
  end
  return true
end

-- Shows a hidden pane again in its original position, without moving
-- focus away from the current window.
function M.show_pane(workspace, pane_name)
  local pane = workspace.panes[pane_name]
  if not pane or not pane.hidden or not vim.api.nvim_tabpage_is_valid(workspace.tabpage) then
    return false
  end
  local current = vim.api.nvim_get_current_win()
  local position
  for index, name in ipairs(workspace.order) do
    if name == pane_name then
      position = index
    end
  end
  -- Split next to the nearest visible neighbour on the pane's side.
  local anchor, command
  for index = position - 1, 1, -1 do
    if M.pane_visible(workspace, workspace.order[index]) then
      anchor, command = workspace.panes[workspace.order[index]].window, "rightbelow vsplit"
      break
    end
  end
  if not anchor then
    for index = position + 1, #workspace.order do
      if M.pane_visible(workspace, workspace.order[index]) then
        anchor, command = workspace.panes[workspace.order[index]].window, "leftabove vsplit"
        break
      end
    end
  end
  if not anchor then
    return false
  end
  local window
  vim.api.nvim_win_call(anchor, function()
    vim.cmd(command)
    window = vim.api.nvim_get_current_win()
  end)
  vim.api.nvim_win_set_buf(window, pane.buffer)
  ui_window.decorate(window, pane.buffer, pane.buffer_name, {
    title = pane.title or workspace.options.title,
    statusline = workspace.options.statusline,
  })
  pane.window = window
  pane.hidden = false
  workspace.lifecycle.track_window(window)
  apply_widths(workspace)
  if pane.last_view then
    ui_render.render(pane.buffer, pane.last_view)
    ui_text_frame.sync(pane, pane.last_view)
  end
  if vim.api.nvim_win_is_valid(current) then
    vim.api.nvim_set_current_win(current)
  end
  if workspace.options.on_pane_toggled then
    workspace.options.on_pane_toggled(pane_name, true)
  end
  return true
end

-- Hides a visible pane or shows a hidden one; returns whether it is now
-- visible.
function M.toggle_pane(workspace, pane_name)
  if M.pane_visible(workspace, pane_name) then
    M.hide_pane(workspace, pane_name)
  else
    M.show_pane(workspace, pane_name)
  end
  return M.pane_visible(workspace, pane_name)
end

function M.render_workspace(workspace, views)
  for pane_name, pane in pairs(workspace.panes) do
    local view = views[pane_name]
    if view and vim.api.nvim_buf_is_valid(pane.buffer) then
      pane.last_view = view
      ui_render.render(pane.buffer, view)
      if not pane.hidden then
        ui_text_frame.sync(pane, view)
      end
    end
  end
end

function M.workspace_buffer(workspace, pane_name)
  local pane = workspace.panes[pane_name]
  return pane and pane.buffer or nil
end

-- The pane's window, or nil while the pane is hidden.
function M.workspace_window(workspace, pane_name)
  local pane = workspace.panes[pane_name]
  return pane and not pane.hidden and pane.window or nil
end

function M.focus_workspace_pane(workspace, pane_name)
  local pane = workspace.panes[pane_name]
  if pane and not pane.hidden and pane.window and vim.api.nvim_win_is_valid(pane.window) then
    vim.api.nvim_set_current_win(pane.window)
    return true
  end
  return false
end

function M.close_workspace(workspace)
  if not workspace then
    return
  end
  workspace.close()
end

return M
