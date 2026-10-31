local ui_config = require("proud.ui.config")
local ui_geometry = require("proud.ui.geometry")
local ui_header = require("proud.ui.header")
local ui_lifecycle = require("proud.ui.lifecycle")
local ui_render = require("proud.ui.render")
local ui_selector = require("proud.ui.selector")
local ui_window = require("proud.ui.window")

local M = {}

function M.open_rounded_pair(views, options)
  options = options or {}
  vim.cmd("tabnew")
  local tabpage = vim.api.nvim_get_current_tabpage()
  local tab_initial_buffer = vim.api.nvim_get_current_buf()
  local backdrop = ui_window.buffer(options.backdrop_name or "proud://surface/backdrop")
  local backdrop_window = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(backdrop_window, backdrop)
  ui_window.decorate(backdrop_window, backdrop, options.backdrop_name or "proud://surface/backdrop", {
    title = options.title or "proud",
    statusline = options.statusline or options.title or "proud",
  })

  local list_buffer = ui_window.buffer(options.list_name or "proud://prs/list")
  local preview_buffer = ui_window.buffer(options.preview_name or "proud://prs/preview")
  local configured_layout = options.windows and ui_config.configure(options.windows) or ui_config.layout_config()
  local function geometry()
    return ui_geometry.surface(vim.o.columns, vim.o.lines, configured_layout)
  end
  local initial_geometry = geometry()

  local function config(row, col, width, height, focusable, creating)
    return {
      relative = "editor",
      row = row,
      col = col,
      width = width,
      height = height,
      border = "rounded",
      focusable = focusable,
      style = "minimal",
      noautocmd = creating or nil,
    }
  end

  local list_window = vim.api.nvim_open_win(
    list_buffer,
    true,
    config(initial_geometry.row, initial_geometry.left_col, initial_geometry.left_width, initial_geometry.height, true, true)
  )
  local preview_window = vim.api.nvim_open_win(
    preview_buffer,
    false,
    config(initial_geometry.row, initial_geometry.right_col, initial_geometry.right_width, initial_geometry.height, true, true)
  )
  ui_window.decorate(list_window, list_buffer, options.list_name or "proud://prs/list", {
    title = options.list_title or "pull requests",
    statusline = options.statusline or "pull requests",
    cursorline = false,
    hide_cursor = true,
    normal_group = "ProudBackground",
    normal_nc_group = "ProudBackground",
    float_group = "ProudBackground",
  })
  ui_window.decorate(preview_window, preview_buffer, options.preview_name or "proud://prs/preview", {
    title = options.preview_title or "Preview",
    statusline = options.statusline or "Preview",
    cursorline = false,
    hide_cursor = false,
    normal_group = "ProudBackground",
    normal_nc_group = "ProudBackground",
    float_group = "ProudBackground",
    float_border = "ProudPreviewBorder",
    float_title = "ProudPreviewTitle",
  })
  vim.wo[preview_window].winhighlight = table.concat({
    "Normal:ProudBackground",
    "NormalNC:ProudBackground",
    "EndOfBuffer:ProudBorder",
    "StatusLine:ProudPanel",
    "StatusLineNC:ProudPanel",
    "TabLine:ProudPanel",
    "TabLineSel:ProudTabActive",
    "WinSeparator:ProudBorder",
    "NormalFloat:ProudBackground",
    "FloatBorder:ProudPreviewBorder",
    "FloatTitle:ProudPreviewTitle",
    "CursorLine:ProudSelection",
    "Cursor:ProudAccent",
    "lCursor:ProudAccent",
    "CursorIM:ProudAccent",
  }, ",")
  ui_render.render(list_buffer, views.list or { lines = {} }, { top_pad = 2 })
  ui_render.render(preview_buffer, views.preview or { lines = {} }, { top_pad = 2 })
  local headers = options.headers or {}
  local list_header = ui_header.open(list_window, vim.tbl_extend("force", {
    buffer_name = options.list_header_name or "proud://headers/list",
    title = "pull request filters",
    prompt = "PR > ",
    placeholder = "...",
    prompt_segments = {
      { text = "PR", group = "ProudAccentText" },
      { text = " > ", group = "ProudBorder" },
    },
    value_group = "ProudBright",
    placeholder_group = "ProudMuted",
    inside = true,
  }, headers.list or {}))
  local preview_header = ui_header.open(preview_window, vim.tbl_extend("force", {
    buffer_name = options.preview_header_name or "proud://headers/preview",
    title = "preview",
    text = "Preview",
    text_group = "ProudPreviewBorder",
    normal_group = "ProudBackground",
    border_group = "ProudPreviewBorder",
    focusable = false,
    inside = true,
  }, headers.preview or {}))
  local list_header_separator = ui_header.separator(list_window, {
    buffer_name = options.list_separator_name or "proud://headers/list-separator",
    group = "ProudBorder",
    inside = true,
  })
  local preview_header_separator = ui_header.separator(preview_window, {
    buffer_name = options.preview_separator_name or "proud://headers/preview-separator",
    group = "ProudBorder",
    inside = true,
  })
  local selector
  if options.selector then
    selector = ui_selector.open_bar(vim.tbl_extend("force", {
      placement = function()
        local current = geometry()
        return {
          row = math.max(current.top, current.row - 2),
          col = current.left_col,
          width = current.available_width,
        }
      end,
      buffer_name = "proud://selector",
    }, options.selector))
  end
  vim.api.nvim_set_current_win(list_window)

  local surface = {
    tabpage = tabpage,
    buffer = list_buffer,
    window = list_window,
    backdrop_window = backdrop_window,
    selector = selector,
    order = { "list", "preview" },
    panes = {
      list = {
        name = "list",
        buffer = list_buffer,
        window = list_window,
        header = list_header,
        header_separator = list_header_separator,
        width = vim.api.nvim_win_get_width(list_window),
      },
      preview = {
        name = "preview",
        buffer = preview_buffer,
        window = preview_window,
        header = preview_header,
        header_separator = preview_header_separator,
        width = vim.api.nvim_win_get_width(preview_window),
      },
    },
  }

  function surface.focus_preview()
    if not vim.api.nvim_win_is_valid(preview_window) then
      return false
    end
    vim.api.nvim_set_current_win(preview_window)
    vim.o.guicursor = "a:block-ProudAccent"
    local line_count = vim.api.nvim_buf_line_count(preview_buffer)
    local row = math.max(1, math.min(line_count, 3))
    pcall(vim.api.nvim_win_set_cursor, preview_window, { row, 0 })
    return true
  end

  function surface.focus_list()
    if not vim.api.nvim_win_is_valid(list_window) then
      return false
    end
    vim.api.nvim_set_current_win(list_window)
    vim.o.guicursor = "a:block-ProudCursorHidden"
    return true
  end

  function surface.resize()
    if not vim.api.nvim_tabpage_is_valid(tabpage) then
      return false
    end
    local next_geometry = geometry()
    vim.api.nvim_win_set_config(list_window, config(
      next_geometry.row,
      next_geometry.left_col,
      next_geometry.left_width,
      next_geometry.height,
      true
    ))
    vim.api.nvim_win_set_config(preview_window, config(
      next_geometry.row,
      next_geometry.right_col,
      next_geometry.right_width,
      next_geometry.height,
      false
    ))
    if list_header then
      list_header.resize()
    end
    if preview_header then
      preview_header.resize()
    end
    if list_header_separator then
      list_header_separator.render()
    end
    if preview_header_separator then
      preview_header_separator.render()
    end
    if selector then
      selector.resize()
    end
    surface.panes.list.width = next_geometry.left_width
    surface.panes.preview.width = next_geometry.right_width
    if options.on_resize then
      options.on_resize(surface)
    end
    return true
  end

  local owned_buffers = {
    tab_initial_buffer,
    backdrop,
    list_buffer,
    preview_buffer,
    list_header and list_header.buffer,
    preview_header and preview_header.buffer,
    list_header_separator and list_header_separator.buffer,
    preview_header_separator and preview_header_separator.buffer,
    selector and selector.buffer,
  }
  local lifecycle = ui_lifecycle.create_scene_lifecycle({
    tabpage = tabpage,
    on_close = options.on_close,
    on_closed = options.on_closed,
  })
  local owned_windows = {
    backdrop_window,
    list_window,
    preview_window,
    list_header and list_header.window,
    preview_header and preview_header.window,
    list_header_separator and list_header_separator.window,
    preview_header_separator and preview_header_separator.window,
    selector and selector.window,
  }
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
  return surface
end

return M
