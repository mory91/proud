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
      weight = pane.weight or 1,
      width = widths[index],
      -- Views are rebuilt on every render and never mutated, so keeping a
      -- reference is enough for re-rendering on resize.
      last_view = pane.view or { lines = {} },
    }
    table.insert(workspace.order, pane.name)
    table.insert(workspace.owned_buffers, buffer)
    ui_render.render(buffer, pane.view or { lines = {} })
    ui_text_frame.sync(workspace.panes[pane.name], pane.view)
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

function M.resize_workspace(workspace)
  if not vim.api.nvim_tabpage_is_valid(workspace.tabpage) then
    return
  end
  local weights = {}
  for _, pane_name in ipairs(workspace.order) do
    table.insert(weights, workspace.panes[pane_name].weight)
  end
  local widths = ui_geometry.workspace_widths(weights, vim.o.columns)
  workspace.widths = vim.deepcopy(widths)
  for index, pane_name in ipairs(workspace.order) do
    local pane = workspace.panes[pane_name]
    pane.width = widths[index]
    if index < #workspace.order then
      pcall(vim.api.nvim_win_set_width, pane.window, widths[index])
    end
  end
  for index, pane_name in ipairs(workspace.order) do
    local pane = workspace.panes[pane_name]
    if pane.last_view and vim.api.nvim_buf_is_valid(pane.buffer) then
      ui_render.render(pane.buffer, pane.last_view)
      ui_text_frame.sync(pane, pane.last_view)
    end
  end
  if workspace.options.on_resize then
    workspace.options.on_resize(workspace)
  end
end

function M.render_workspace(workspace, views)
  for pane_name, pane in pairs(workspace.panes) do
    local view = views[pane_name]
    if view and vim.api.nvim_buf_is_valid(pane.buffer) then
      pane.last_view = view
      ui_render.render(pane.buffer, view)
      ui_text_frame.sync(pane, view)
    end
  end
end

function M.workspace_buffer(workspace, pane_name)
  local pane = workspace.panes[pane_name]
  return pane and pane.buffer or nil
end

function M.workspace_window(workspace, pane_name)
  local pane = workspace.panes[pane_name]
  return pane and pane.window or nil
end

function M.focus_workspace_pane(workspace, pane_name)
  local pane = workspace.panes[pane_name]
  if pane and vim.api.nvim_win_is_valid(pane.window) then
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
