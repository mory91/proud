local ui = require("proud.ui")
local state = require("proud.session").current.state
local surface = state and state.surface
local list = surface and surface.panes and surface.panes.list
local preview = surface and surface.panes and surface.panes.preview
local list_header = list and list.header
local preview_header = preview and preview.header
local list_separator = list and list.header_separator
local preview_separator = preview and preview.header_separator
local selector = surface and surface.selector

local function rounded(border)
  return type(border) == "table" and border[1] == "╭" and border[3] == "╮" and border[7] == "╰" and border[8] == "│"
end

local checks = {}
local function check(name, value)
  checks[name] = not not value
end

check("surface", state and surface and #surface.order == 2)
check("panes", list and preview and list.buffer ~= preview.buffer)
check("windows", list and preview and vim.api.nvim_win_is_valid(list.window) and vim.api.nvim_win_is_valid(preview.window))
check("headers", list_header and preview_header and list_separator and preview_separator)
check("selector", selector and vim.api.nvim_win_is_valid(selector.window))
if list and preview and list_header and preview_header and list_separator and preview_separator then
  local list_config = vim.api.nvim_win_get_config(list.window)
  local preview_config = vim.api.nvim_win_get_config(preview.window)
  local list_header_config = vim.api.nvim_win_get_config(list_header.window)
  local preview_header_config = vim.api.nvim_win_get_config(preview_header.window)
  local list_separator_config = vim.api.nvim_win_get_config(list_separator.window)
  local preview_separator_config = vim.api.nvim_win_get_config(preview_separator.window)
  local top = (vim.o.showtabline == 2 or (vim.o.showtabline == 1 and vim.fn.tabpagenr("$") > 1)) and 1 or 0
  local bottom = vim.o.cmdheight + (vim.o.laststatus > 0 and 1 or 0)
  local layout = ui.layout_config()
  local margin = layout.margin
  check("rounded", rounded(list_config.border) and rounded(preview_config.border))
  check("titles", (not list_config.title or list_config.title == "") and (not preview_config.title or preview_config.title == ""))
  check("relative", list_config.relative == "editor" and preview_config.relative == "editor")
  check("header_rows", list_header_config.row == list_config.row + 1 and preview_header_config.row == preview_config.row + 1)
  check("separator_rows", list_separator_config.row == list_config.row + 2 and preview_separator_config.row == preview_config.row + 2)
  check("header_columns", list_header_config.col == list_config.col + 1 and preview_header_config.col == preview_config.col + 1)
  check("separator_columns", list_separator_config.col == list_config.col + 1 and preview_separator_config.col == preview_config.col + 1)
  check("separator_widths", list_separator_config.width == list_config.width and preview_separator_config.width == preview_config.width)
  check("gap", preview_config.col - (list_config.col + list_config.width) == layout.gap)
  check("top_margin", list_config.row - 1 >= top + margin.top and preview_config.row - 1 >= top + margin.top)
  check("bottom_margin", list_config.row + list_config.height + 1 <= vim.o.lines - bottom - margin.bottom and preview_config.row + preview_config.height + 1 <= vim.o.lines - bottom - margin.bottom)
  check("list_prompt", table.concat(vim.api.nvim_buf_get_lines(list_header.buffer, 0, -1, false), "\n"):find("PR > ", 1, true) ~= nil)
  check("preview_title", table.concat(vim.api.nvim_buf_get_lines(preview_header.buffer, 0, -1, false), "\n"):find("Preview", 1, true) ~= nil)
  check("list_separator", vim.api.nvim_buf_get_lines(list_separator.buffer, 0, 1, false)[1] == string.rep("─", list_separator_config.width))
  check("preview_separator", vim.api.nvim_buf_get_lines(preview_separator.buffer, 0, 1, false)[1] == string.rep("─", preview_separator_config.width))
  if selector then
    local selector_config = vim.api.nvim_win_get_config(selector.window)
    check("selector_row", selector_config.row == list_config.row - 2)
    check("selector_columns", selector_config.col == list_config.col and selector_config.width == list_config.width + layout.gap + preview_config.width)
    check("selector_outside", selector_config.row + selector_config.height <= list_config.row)
    local selector_lines = vim.api.nvim_buf_get_lines(selector.buffer, 0, -1, false)
    check("selector_height", selector_config.height == 1 and #selector_lines == 1)
    local selector_line = selector_lines[1] or ""
    check("selector_straight", #selector_lines == 1 and vim.fn.strdisplaywidth(selector_line) == selector_config.width)
    check("selector_unoutlined", selector_line:find("╭", 1, true) == nil and selector_line:find("╰", 1, true) == nil)
    local required_labels = { "All open" }
    if selector_config.width >= 76 then
      required_labels = { "Review requested", "Mine", "All open", "Recently viewed", "Branches" }
    end
    for _, label in ipairs(required_labels) do
      check("selector_" .. label:gsub("%s+", "_"):lower(), selector_line:find(label, 1, true) ~= nil)
    end
    local selector_namespace = vim.api.nvim_get_namespaces().proud
    local selector_marks = vim.api.nvim_buf_get_extmarks(selector.buffer, selector_namespace, 0, -1, { details = true })
    local function selector_color(label, group)
      local start_col = selector_line:find(label, 1, true)
      if not start_col then
        return false
      end
      start_col = start_col - 1
      local expected_group = vim.api.nvim_get_hl_id_by_name(group)
      for _, mark in ipairs(selector_marks) do
        local detail = mark[4] or {}
        if (detail.hl_group == group or detail.hl_group == expected_group)
          and (detail.col or mark[3]) <= start_col
          and (detail.end_col or start_col + #label) >= start_col + #label
        then
          return true
        end
      end
      return false
    end
    check("selector_selected_color", selector_color("All open", "ProudAccent"))
    if selector_config.width >= 76 then
      check("selector_unselected_color", selector_color("Mine", "ProudMuted"))
    end
  end
  local namespace = vim.api.nvim_get_namespaces().proud
  local function separator_has_one_full_color(separator, group)
    local line = vim.api.nvim_buf_get_lines(separator.buffer, 0, 1, false)[1] or ""
    local marks = vim.api.nvim_buf_get_extmarks(separator.buffer, namespace, 0, -1, { details = true })
    if #marks ~= 1 then
      return false
    end
    local detail = marks[1][4] or {}
    local expected_group = vim.api.nvim_get_hl_id_by_name(group)
    return detail.end_col == #line
      and (detail.hl_group == group or detail.hl_group == expected_group)
  end
  check("list_separator_color", separator_has_one_full_color(list_separator, "ProudBorder"))
  check("preview_separator_color", separator_has_one_full_color(preview_separator, "ProudBorder"))
  local function top_border_is_clear(config)
    local screen_row = math.floor(config.row) + 1
    local expected = "╭" .. string.rep("─", math.floor(config.width)) .. "╮"
    local actual = {}
    for column = math.floor(config.col) + 1, math.floor(config.col) + math.floor(config.width) + 2 do
      table.insert(actual, vim.fn.screenstring(screen_row, column))
    end
    return table.concat(actual) == expected
  end
  check("list_top_border", top_border_is_clear(list_config))
  check("preview_top_border", top_border_is_clear(preview_config))
  for _, pane in ipairs({ list, preview }) do
    local width = vim.api.nvim_win_get_width(pane.window)
    vim.api.nvim_win_set_option(pane.window, "wrap", false)
    vim.api.nvim_win_set_option(pane.window, "linebreak", false)
    local straight = true
    for _, line in ipairs(vim.api.nvim_buf_get_lines(pane.buffer, 0, -1, false)) do
      if vim.fn.strdisplaywidth(line) ~= width then
        straight = false
      end
    end
    check(pane.name .. "_straight", straight)
  end
  check("surface_resize_api", type(surface.resize) == "function")
  vim.g.PROUD_LAYOUT_SNAPSHOT = vim.json.encode({
    columns = vim.o.columns,
    lines = vim.o.lines,
    row = list_config.row,
    col = list_config.col,
    width = list_config.width,
    height = list_config.height,
    preview_row = preview_config.row,
    preview_col = preview_config.col,
    preview_width = preview_config.width,
    preview_height = preview_config.height,
  })
end

local failures = {}
for name, passed in pairs(checks) do
  if not passed then
    table.insert(failures, name)
  end
end
table.sort(failures)
local ok = #failures == 0
vim.api.nvim_echo({
  { "SIZE_OK=" .. tostring(ok) .. (ok and "" or " failures=" .. table.concat(failures, ",")) },
}, false, {})
