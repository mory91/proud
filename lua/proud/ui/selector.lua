local ui_float = require("proud.ui.float")
local ui_render = require("proud.ui.render")
local ui_text = require("proud.ui.text")
local ui_window = require("proud.ui.window")

local M = {}

function M.button_style(options)
  options = options or {}
  return {
    selected_group = options.selected_group or "ProudAccent",
    item_group = options.item_group or "ProudMuted",
    selected_padding = options.selected_padding or 2,
    item_padding = options.item_padding or 1,
    height = math.max(1, math.floor(tonumber(options.height) or 1)),
  }
end

function M.button_layout(items, selected, width, options)
  items = items or {}
  selected = math.max(1, math.min(#items, math.floor(tonumber(selected) or 1)))
  width = math.max(1, math.floor(tonumber(width) or 1))
  local style = M.button_style(options)
  local visible = {}
  for index = 1, #items do
    table.insert(visible, index)
  end
  local function labels()
    local values = {}
    for _, index in ipairs(visible) do
      local item = items[index]
      local value = type(item) == "table" and (item.label or item.text) or item
      table.insert(values, tostring(value or ""))
    end
    return values
  end
  local function minimum_width(values)
    local total = math.max(0, #values - 1) + #values * 2
    for _, value in ipairs(values) do
      total = total + math.min(1, ui_text.display_width(value))
    end
    return total
  end
  local values = labels()
  while #visible > 1 and minimum_width(values) > width do
    local remove_position
    local remove_distance = -1
    for position, index in ipairs(visible) do
      local distance = math.abs(index - selected)
      if distance > remove_distance then
        remove_distance = distance
        remove_position = position
      end
    end
    table.remove(visible, remove_position)
    values = labels()
  end

  local separator_width = #values > 1 and math.floor((width - #values * 3) / #values) < 3 and 1 or 2
  local target_labels = math.max(#values, width - math.max(0, #values - 1) * separator_width - #values * 2)
  local label_widths = {}
  local used = 0
  for index, value in ipairs(values) do
    label_widths[index] = math.min(1, ui_text.display_width(value))
    used = used + label_widths[index]
  end
  while used < target_labels do
    local grew = false
    for index, value in ipairs(values) do
      if used >= target_labels then
        break
      end
      if label_widths[index] < ui_text.display_width(value) then
        label_widths[index] = label_widths[index] + 1
        used = used + 1
        grew = true
      end
    end
    if not grew then
      break
    end
  end

  local segments = {}
  local highlights = {}
  local text = ""
  for position, value in ipairs(values) do
    local fitted = ui_text.fit(value, label_widths[position]):gsub("%s+$", "")
    local is_selected = visible[position] == selected
    local selected_padding = string.rep(" ", style.selected_padding)
    local item_padding = string.rep(" ", style.item_padding)
    local segment = is_selected
      and (selected_padding .. fitted .. selected_padding)
      or (item_padding .. fitted .. item_padding)
    if position > 1 then
      text = text .. string.rep(" ", separator_width)
    end
    local start_col = #text
    text = text .. segment
    table.insert(highlights, {
      0,
      start_col,
      #text,
      is_selected and style.selected_group or style.item_group,
    })
  end
  text = ui_text.fit(text, width)
  return {
    lines = { text },
    text = text,
    highlights = highlights,
    selected = selected,
  }
end

function M.open_bar(options)
  options = options or {}
  local selected = math.max(1, math.min(#(options.items or {}), math.floor(tonumber(options.selected) or 1)))
  local width = math.max(1, math.floor(tonumber(options.width) or 1))
  local style = M.button_style(options)
  local height = style.height
  local buffer = ui_window.buffer(options.buffer_name or "proud://selector")
  local function render()
    local view = M.button_layout(options.items, selected, width, options)
    ui_render.render(buffer, { lines = { view.text }, highlights = view.highlights })
  end
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].modifiable = false
  -- options.placement() supplies live { row, col, width }; otherwise the
  -- bar stays at the static options.row / options.col / options.width.
  local function placement()
    local place = options.placement and options.placement() or {
      row = options.row,
      col = options.col,
      width = width,
    }
    return {
      row = math.max(0, math.floor(tonumber(place.row) or 0)),
      col = math.max(0, math.floor(tonumber(place.col) or 0)),
      width = math.max(1, math.floor(tonumber(place.width) or width)),
      height = height,
      focusable = false,
      zindex = options.zindex or 51,
    }
  end
  local frame = ui_float.create(buffer, { placement = placement })
  local window = frame.window
  width = vim.api.nvim_win_get_width(window)
  vim.wo[window].winhighlight = table.concat({
    "Normal:ProudBackground",
    "NormalNC:ProudBackground",
    "NormalFloat:ProudBackground",
    "EndOfBuffer:ProudBackground",
  }, ",")
  vim.wo[window].number = false
  vim.wo[window].relativenumber = false
  vim.wo[window].signcolumn = "no"
  vim.wo[window].cursorline = false
  vim.wo[window].wrap = false
  vim.wo[window].linebreak = false
  render()
  return {
    buffer = buffer,
    window = window,
    get_selected = function()
      return selected
    end,
    resize = function()
      if not frame.reposition() then
        return
      end
      local config = vim.api.nvim_win_get_config(window)
      local current_width = math.max(1, math.floor(tonumber(config.width) or width))
      width = current_width
      render()
    end,
    set_selected = function(value, notify)
      local next_value = math.max(1, math.min(#(options.items or {}), math.floor(tonumber(value) or 1)))
      if next_value == selected then
        return
      end
      selected = next_value
      render()
      if notify and options.on_change then
        options.on_change(selected, options.items[selected])
      end
    end,
  }
end

return M
