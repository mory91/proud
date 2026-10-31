-- Rounded two-pane surface: a backdrop tab with two bordered floats side by
-- side, optional in-pane headers and separators, and an optional selector
-- bar above them. Everything feature-specific (names, titles, prompts,
-- highlight choices) comes from the caller's pane specs.
local ui_config = require("proud.ui.config")
local ui_geometry = require("proud.ui.geometry")
local ui_header = require("proud.ui.header")
local ui_lifecycle = require("proud.ui.lifecycle")
local ui_render = require("proud.ui.render")
local ui_selector = require("proud.ui.selector")
local ui_window = require("proud.ui.window")

local M = {}

-- Cursor shapes applied when a pane takes focus.
M.cursor = {
  hidden = "a:block-ProudCursorHidden",
  accent = "a:block-ProudAccent",
}

local function pane_config(rect, focusable, creating)
  return {
    relative = "editor",
    row = rect.row,
    col = rect.col,
    width = rect.width,
    height = rect.height,
    border = "rounded",
    focusable = focusable,
    style = "minimal",
    noautocmd = creating or nil,
  }
end

-- Opens a two-pane surface.
--
-- spec = {
--   title, statusline, backdrop_name, windows, selector, focus,
--   on_resize(surface), on_close(lifecycle), on_closed(lifecycle),
--   panes = { left_spec, right_spec },
-- }
-- pane spec = {
--   name, buffer_name, view, title, statusline,
--   top_pad = 0,             -- blank rows reserved above content (headers)
--   focusable = true,        -- used for both open and resize
--   cursor = "hidden" | "accent" | nil,   -- cursor shape when focused
--   focus_row = nil,         -- cursor row to jump to on focus
--   decorate = {...},        -- extra ui.window.decorate options
--   header = {...} | nil,    -- ui.header.open options (opened inside)
--   separator = group | nil, -- draws a header separator in that group
-- }
function M.open_pair(spec)
  assert(spec and spec.panes and #spec.panes == 2, "open_pair needs exactly two pane specs")
  vim.cmd("tabnew")
  local tabpage = vim.api.nvim_get_current_tabpage()
  local tab_initial_buffer = vim.api.nvim_get_current_buf()
  local backdrop_name = spec.backdrop_name or "proud://surface/backdrop"
  local backdrop = ui_window.buffer(backdrop_name)
  local backdrop_window = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(backdrop_window, backdrop)
  ui_window.decorate(backdrop_window, backdrop, backdrop_name, {
    title = spec.title or "proud",
    statusline = spec.statusline or spec.title or "proud",
  })

  local configured_layout = spec.windows and ui_config.configure(spec.windows) or ui_config.layout_config()
  local function geometry()
    return ui_geometry.surface(vim.o.columns, vim.o.lines, configured_layout)
  end
  local function rects(g)
    return {
      { row = g.row, col = g.left_col, width = g.left_width, height = g.height },
      { row = g.row, col = g.right_col, width = g.right_width, height = g.height },
    }
  end

  local surface = {
    tabpage = tabpage,
    backdrop_window = backdrop_window,
    order = {},
    panes = {},
  }
  local owned_buffers = { tab_initial_buffer, backdrop }
  local owned_windows = { backdrop_window }

  local initial_rects = rects(geometry())
  for index, pane_spec in ipairs(spec.panes) do
    local buffer_name = pane_spec.buffer_name or ("proud://surface/" .. pane_spec.name)
    local buffer = ui_window.buffer(buffer_name)
    local focusable = pane_spec.focusable ~= false
    local window = vim.api.nvim_open_win(buffer, index == 1, pane_config(initial_rects[index], focusable, true))
    ui_window.decorate(window, buffer, buffer_name, vim.tbl_extend("force", {
      title = pane_spec.title,
      statusline = pane_spec.statusline or spec.statusline or pane_spec.title,
      cursorline = false,
      hide_cursor = pane_spec.cursor == "hidden",
    }, pane_spec.decorate or {}))
    surface.panes[pane_spec.name] = {
      name = pane_spec.name,
      spec = pane_spec,
      buffer = buffer,
      window = window,
      focusable = focusable,
      width = vim.api.nvim_win_get_width(window),
    }
    table.insert(surface.order, pane_spec.name)
    table.insert(owned_buffers, buffer)
    table.insert(owned_windows, window)
  end

  for _, name in ipairs(surface.order) do
    local pane = surface.panes[name]
    local pane_spec = pane.spec
    ui_render.render(pane.buffer, pane_spec.view or { lines = {} }, { top_pad = pane_spec.top_pad or 0 })
    if pane_spec.header then
      pane.header = ui_header.open(pane.window, vim.tbl_extend("force", { inside = true }, pane_spec.header))
      table.insert(owned_buffers, pane.header.buffer)
      table.insert(owned_windows, pane.header.window)
    end
    if pane_spec.separator then
      pane.header_separator = ui_header.separator(pane.window, {
        buffer_name = pane_spec.separator_buffer_name,
        group = pane_spec.separator,
        inside = true,
      })
      table.insert(owned_buffers, pane.header_separator.buffer)
      table.insert(owned_windows, pane.header_separator.window)
    end
  end

  if spec.selector then
    surface.selector = ui_selector.open_bar(vim.tbl_extend("force", {
      placement = function()
        local current = geometry()
        return {
          row = math.max(current.top, current.row - 2),
          col = current.left_col,
          width = current.available_width,
        }
      end,
      buffer_name = "proud://selector",
    }, spec.selector))
    table.insert(owned_buffers, surface.selector.buffer)
    table.insert(owned_windows, surface.selector.window)
  end

  local first = surface.panes[surface.order[1]]
  surface.buffer = first.buffer
  surface.window = first.window

  -- Focuses a pane by name, applying its cursor shape and focus row.
  function surface.focus(name)
    local pane = surface.panes[name]
    if not pane or not vim.api.nvim_win_is_valid(pane.window) then
      return false
    end
    vim.api.nvim_set_current_win(pane.window)
    local shape = M.cursor[pane.spec.cursor]
    if shape then
      vim.o.guicursor = shape
    end
    if pane.spec.focus_row then
      local line_count = vim.api.nvim_buf_line_count(pane.buffer)
      local row = math.max(1, math.min(line_count, pane.spec.focus_row))
      pcall(vim.api.nvim_win_set_cursor, pane.window, { row, 0 })
    end
    return true
  end

  function surface.resize()
    if not vim.api.nvim_tabpage_is_valid(tabpage) then
      return false
    end
    local next_rects = rects(geometry())
    for index, name in ipairs(surface.order) do
      local pane = surface.panes[name]
      if vim.api.nvim_win_is_valid(pane.window) then
        vim.api.nvim_win_set_config(pane.window, pane_config(next_rects[index], pane.focusable))
      end
      pane.width = next_rects[index].width
      if pane.header then
        pane.header.resize()
      end
      if pane.header_separator then
        pane.header_separator.render()
      end
    end
    if surface.selector then
      surface.selector.resize()
    end
    if spec.on_resize then
      spec.on_resize(surface)
    end
    return true
  end

  local lifecycle = ui_lifecycle.create_scene_lifecycle({
    tabpage = tabpage,
    on_close = spec.on_close,
    on_closed = spec.on_closed,
  })
  for _, buffer in ipairs(owned_buffers) do
    lifecycle.track_buffer(buffer)
  end
  for _, window in ipairs(owned_windows) do
    lifecycle.track_window(window)
  end
  vim.api.nvim_create_autocmd("VimResized", {
    group = lifecycle.group,
    callback = function()
      if vim.api.nvim_tabpage_is_valid(tabpage) then
        surface.resize()
      end
    end,
  })
  surface.lifecycle = lifecycle
  surface.close = lifecycle.close

  surface.focus(spec.focus or surface.order[1])
  return surface
end

return M
