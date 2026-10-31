local M = {}

M.default_guicursor = vim.o.guicursor

function M.title_for(name)
  if name == "proud://prs" then
    return "proud: pull requests"
  end
  if name == "proud://prs/preview" then
    return "Preview"
  end
  if name:match("^proud://help") then
    return "Proud help"
  end
  local number, mode = name:match("^proud://pr/(%d+)/diff/(%w+)$")
  if number then
    return ("#%s diff · %s"):format(number, mode)
  end
  number = name:match("^proud://pr/(%d+)/overview$")
  if number then
    return ("#%s overview"):format(number)
  end
  local compare = name:match("^proud://compare/(.+)$")
  if compare then
    return "compare  " .. compare
  end
  return name:gsub("^proud://", "")
end

function M.decorate(window, buffer, name, options)
  options = options or {}
  vim.o.guicursor = options.hide_cursor and "a:block-ProudCursorHidden" or M.default_guicursor
  local normal_group = options.normal_group or "ProudBackground"
  local normal_nc_group = options.normal_nc_group or normal_group
  local float_group = options.float_group or "ProudBackground"
  local float_border = options.float_border or "ProudAccentText"
  local float_title = options.float_title or "ProudAccentText"
  local winhighlight = {
    "Normal:" .. normal_group,
    "NormalNC:" .. normal_nc_group,
    "EndOfBuffer:ProudBorder",
    "StatusLine:ProudPanel",
    "StatusLineNC:ProudPanel",
    "TabLine:ProudPanel",
    "TabLineSel:ProudTabActive",
    "WinSeparator:ProudBorder",
    "NormalFloat:" .. float_group,
    "FloatBorder:" .. float_border,
    "FloatTitle:" .. float_title,
    "CursorLine:ProudSelection",
  }
  if options.hide_cursor then
    table.insert(winhighlight, "Cursor:ProudCursorHidden")
    table.insert(winhighlight, "lCursor:ProudCursorHidden")
    table.insert(winhighlight, "CursorIM:ProudCursorHidden")
  end
  vim.wo[window].winhighlight = table.concat(winhighlight, ",")
  vim.wo[window].number = false
  vim.wo[window].relativenumber = false
  vim.wo[window].signcolumn = "no"
  vim.wo[window].cursorline = options.cursorline ~= false
  vim.wo[window].wrap = false
  vim.wo[window].linebreak = false
  vim.wo[window].breakindent = false
  vim.wo[window].showbreak = ""
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
    "%#ProudMuted# GitHub ",
    "%#ProudSuccessText# api ",
    "%#ProudSuccess#✓ ",
    "%#ProudPanel# ",
  })
end

function M.buffer(name)
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buffer) and vim.api.nvim_buf_get_name(buffer) == name then
      vim.bo[buffer].buftype = "nofile"
      vim.bo[buffer].bufhidden = "hide"
      vim.bo[buffer].swapfile = false
      vim.bo[buffer].modifiable = false
      vim.b[buffer].proud_buffer = true
      return buffer
    end
  end
  local buffer = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, buffer, name)
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "hide"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].modifiable = false
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
