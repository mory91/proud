local ui_cursor = require("proud.ui.cursor")

local M = {}

-- Fallback tab/status title when a caller passes none: the buffer name
-- without its proud:// scheme. Features pass explicit titles.
function M.title_for(name)
  return (tostring(name or ""):gsub("^proud://", ""))
end

-- Right-hand statusline segments shown in every decorated window, as
-- { { text, group }, ... }. Empty by default; the application sets them
-- (see proud.init setup). Text is inserted verbatim into 'statusline'.
M.status_segments = {}

function M.set_status_segments(segments)
  M.status_segments = segments or {}
end

local function status_right()
  local parts = {}
  for _, segment in ipairs(M.status_segments) do
    parts[#parts + 1] = "%#" .. segment[2] .. "#" .. segment[1]
  end
  return table.concat(parts)
end

-- Window-local options shared by every Proud window: no gutters, no
-- cursorline, no soft wrapping. Pass overrides for anything that differs.
M.base_options = {
  number = false,
  relativenumber = false,
  signcolumn = "no",
  cursorline = false,
  wrap = false,
  linebreak = false,
  breakindent = false,
}

function M.options(window, overrides)
  for name, value in pairs(M.base_options) do
    if not overrides or overrides[name] == nil then
      vim.wo[window][name] = value
    end
  end
  for name, value in pairs(overrides or {}) do
    vim.wo[window][name] = value
  end
end

-- Builds a 'winhighlight' value from { BuiltinGroup = "ProudGroup" }.
-- Keys are sorted so the result is deterministic.
function M.winhighlight_value(mapping)
  local names = vim.tbl_keys(mapping)
  table.sort(names)
  local parts = {}
  for _, name in ipairs(names) do
    parts[#parts + 1] = name .. ":" .. mapping[name]
  end
  return table.concat(parts, ",")
end

function M.winhighlight(window, mapping)
  vim.wo[window].winhighlight = M.winhighlight_value(mapping)
end

-- Maps the three cursor highlight slots to one group.
function M.cursor_groups(mapping, group)
  mapping.Cursor = group
  mapping.lCursor = group
  mapping.CursorIM = group
  return mapping
end

function M.decorate(window, buffer, name, options)
  options = options or {}
  ui_cursor.set_window(window, options.hide_cursor and "hidden" or options.cursor_shape)
  local normal_group = options.normal_group or "ProudBackground"
  local normal_nc_group = options.normal_nc_group or normal_group
  local float_group = options.float_group or "ProudBackground"
  local float_border = options.float_border or "ProudAccentText"
  local float_title = options.float_title or "ProudAccentText"
  local winhighlight = {
    Normal = normal_group,
    NormalNC = normal_nc_group,
    EndOfBuffer = "ProudBorder",
    StatusLine = "ProudPanel",
    StatusLineNC = "ProudPanel",
    TabLine = "ProudPanel",
    TabLineSel = "ProudTabActive",
    WinSeparator = "ProudBorder",
    NormalFloat = float_group,
    FloatBorder = float_border,
    FloatTitle = float_title,
    CursorLine = "ProudSelection",
  }
  if options.hide_cursor then
    M.cursor_groups(winhighlight, "ProudCursorHidden")
  elseif options.cursor_group then
    M.cursor_groups(winhighlight, options.cursor_group)
  end
  M.winhighlight(window, winhighlight)
  M.options(window, { cursorline = options.cursorline ~= false, showbreak = "" })
  vim.b[buffer].proud_title = options.title or M.title_for(name)
  vim.wo[window].statusline = table.concat({
    "%#ProudAccent# NORMAL ",
    "%#ProudBorder# ▎ ",
    "%#ProudBright# ",
    options.statusline or vim.b[buffer].proud_title,
    " ",
    "%#ProudBorder#▎",
    "%<",
    "%#ProudPanel#%=",
    status_right(),
    "%#ProudPanel# ",
  })
end

-- Buffer-local options every Proud buffer starts with.
M.base_buffer_options = {
  buftype = "nofile",
  bufhidden = "hide",
  swapfile = false,
  modifiable = false,
}

-- Installed on first buffer creation (not at require time): clears the
-- modified flag on Proud buffers so :quit never stops on them.
local quit_guard_installed = false
local function install_quit_guard()
  if quit_guard_installed then
    return
  end
  quit_guard_installed = true
  vim.api.nvim_create_autocmd("QuitPre", {
    group = vim.api.nvim_create_augroup("ProudBufferLifecycle", { clear = true }),
    callback = function()
      for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buffer) and vim.b[buffer].proud_buffer then
          vim.bo[buffer].modified = false
        end
      end
    end,
  })
end

local function find_buffer(name)
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buffer) and vim.api.nvim_buf_get_name(buffer) == name then
      return buffer
    end
  end
end

-- Returns a scratch buffer named `name` (nil for an unnamed one), reusing
-- an existing buffer with that name unless options.reuse == false.
-- options.bo overrides or extends M.base_buffer_options.
function M.buffer(name, options)
  options = options or {}
  install_quit_guard()
  local buffer = name and options.reuse ~= false and find_buffer(name) or nil
  if not buffer then
    buffer = vim.api.nvim_create_buf(false, true)
    if name then
      pcall(vim.api.nvim_buf_set_name, buffer, name)
    end
  end
  local overrides = options.bo or {}
  for option, value in pairs(M.base_buffer_options) do
    if overrides[option] == nil then
      vim.bo[buffer][option] = value
    end
  end
  for option, value in pairs(overrides) do
    vim.bo[buffer][option] = value
  end
  vim.b[buffer].proud_buffer = true
  return buffer
end

local function reveal_window(window, first_row, last_row, column, reserved_rows)
  reserved_rows = math.max(0, math.floor(tonumber(reserved_rows) or 0))
  local height = math.max(1, vim.api.nvim_win_get_height(window))
  local visible_height = math.max(1, height - reserved_rows)
  local line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(window))
  local view = vim.api.nvim_win_call(window, function()
    return vim.fn.winsaveview()
  end)
  local maximum_topline = first_row - reserved_rows
  local minimum_topline = last_row - reserved_rows - visible_height + 1
  local topline = math.max(minimum_topline, math.min(view.topline, maximum_topline))
  topline = math.max(1, math.min(topline, math.max(1, line_count - height + 1)))
  vim.api.nvim_win_call(window, function()
    vim.fn.winrestview({
      topline = topline,
      lnum = first_row,
      col = column,
      leftcol = view.leftcol,
    })
  end)
end

function M.set_cursor(buffer, row, col, visible_through_row, options)
  options = options or {}
  local line_count = vim.api.nvim_buf_line_count(buffer)
  row = math.max(1, math.min(line_count, row))
  local line = vim.api.nvim_buf_get_lines(buffer, row - 1, row, false)[1] or ""
  col = math.max(0, math.min(col or 0, #line))
  for _, window in ipairs(vim.fn.win_findbuf(buffer)) do
    pcall(vim.api.nvim_win_set_cursor, window, { row, col })
    if visible_through_row then
      reveal_window(window, row, math.min(line_count, visible_through_row), col, options.reserved_rows)
    end
  end
end

return M
