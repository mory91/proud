local ui = require("proud.ui")

local M = {
  name = "conversation_cards",
}

local namespace = vim.api.nvim_create_namespace("proud_conversation_cards")
local instance_sequence = 0

local function age_label(value)
  local age = tostring(value or "")
  if age == "" then
    return "now"
  end
  if age:lower():find("now", 1, true) or age:lower():find("ago", 1, true) then
    return age
  end
  return age .. " ago"
end

local function append_segment(line, highlights, row, segment)
  local text = tostring(segment.text or "")
  if text == "" then
    return line
  end
  local start_col = #line
  line = line .. text
  if segment.group then
    table.insert(highlights, {
      line = row,
      start_col = start_col,
      end_col = #line,
      group = segment.group,
    })
  end
  return line
end

local function clip_card(spec, top, host_height)
  if not spec or host_height <= 0 then
    return nil
  end
  local bottom_row = top + spec.height + 1
  local outer_start = math.max(0, top)
  local outer_end = math.min(host_height - 1, bottom_row)
  if outer_start > outer_end then
    return nil
  end

  local top_visible = top >= 0 and top <= outer_end
  local bottom_visible = bottom_row >= outer_start and bottom_row <= outer_end
  local first_line = math.max(1, outer_start - top)
  local last_line = math.min(spec.height, outer_end - top)
  local lines = {}
  local highlights = {}
  if first_line <= last_line then
    for index = first_line, last_line do
      table.insert(lines, spec.lines[index])
    end
    for _, item in ipairs(spec.highlights or {}) do
      if item.line >= first_line - 1 and item.line <= last_line - 1 then
        table.insert(highlights, {
          line = item.line - first_line + 1,
          start_col = item.start_col,
          end_col = item.end_col,
          group = item.group,
        })
      end
    end
  else
    table.insert(lines, " ")
  end

  local row
  if top_visible then
    row = top
  elseif first_line <= last_line then
    row = top + first_line
  else
    row = bottom_row - 1
  end

  return {
    row = row,
    height = #lines,
    lines = lines,
    highlights = highlights,
    top_visible = top_visible,
    bottom_visible = bottom_visible,
    first_line = first_line,
    last_line = last_line,
  }
end

function M.layout(items, options)
  options = options or {}
  local width = math.max(28, math.floor(options.width or 80))
  local host_width = width + (tonumber(options.margin) or 2)
  local start_row = math.max(1, math.floor(options.start_row or 1))
  local gap = math.max(0, math.floor(options.gap or 1))
  local col_offset = math.max(0, math.floor(tonumber(options.col_offset) or 0))
  local min_width = math.max(12, math.floor(tonumber(options.min_width) or 28))
  local cursor = start_row
  local cards = {}
  for _, item in ipairs(items or {}) do
    local depth = math.max(0, math.floor(tonumber(item.depth) or 0))
    local card_width = math.max(min_width, host_width - depth * 2)
    local inner_width = math.max(8, card_width - 4)
    local lines = {}
    local highlights = {}
    local header = " "
    local header_segments = {
      { text = tostring(item.author or "unknown"), group = "ProudAccentText" },
    }
    if item.meta_segments then
      for _, segment in ipairs(item.meta_segments) do
        table.insert(header_segments, segment)
      end
    else
      table.insert(header_segments, {
        text = "  " .. tostring(item.meta or "commented"),
        group = item.meta_group or "ProudMuted",
      })
    end
    table.insert(header_segments, {
      text = "  · " .. age_label(item.age),
      group = "ProudMuted",
    })
    for _, segment in ipairs(header_segments) do
      header = append_segment(header, highlights, 0, segment)
    end
    table.insert(lines, ui.fit(header, card_width))
    local body = tostring(item.body or "")
    if body == "" then
      body = "(no message)"
    end
    for _, body_line in ipairs(ui.wrap_text(body, inner_width)) do
      local row = #lines
      local line = " " .. body_line
      table.insert(lines, ui.fit(line, card_width))
      table.insert(highlights, {
        line = row,
        start_col = 0,
        end_col = #line,
        group = body == "(no message)" and "ProudMuted" or "ProudBright",
      })
    end
    local id = tostring(item.id or ("card:" .. (#cards + 1)))
    table.insert(cards, {
      id = id,
      depth = depth,
      row = cursor,
      col = col_offset + depth * 2,
      width = card_width,
      height = #lines,
      lines = lines,
      highlights = highlights,
      selected_group = item.depth and tonumber(item.depth) > 0 and "ProudCardReply" or "ProudCard",
    })
    cursor = cursor + #lines + 2 + gap
  end
  cards.start_row = start_row
  cards.total_rows = math.max(0, cursor - start_row - gap)
  cards.width = width
  return cards
end

local function set_card_lines(card)
  if not vim.api.nvim_buf_is_valid(card.buffer) then
    return
  end
  local visible = card.visible
  vim.bo[card.buffer].modifiable = true
  vim.api.nvim_buf_set_lines(card.buffer, 0, -1, false, visible.lines)
  vim.bo[card.buffer].modifiable = false
  vim.api.nvim_buf_clear_namespace(card.buffer, namespace, 0, -1)
  for _, item in ipairs(visible.highlights or {}) do
    local line = visible.lines[item.line + 1]
    if line then
      local start_col = math.max(0, math.min(item.start_col or 0, #line))
      local end_col = math.max(start_col, math.min(item.end_col or start_col, #line))
      if end_col > start_col then
        vim.api.nvim_buf_set_extmark(card.buffer, namespace, item.line, start_col, {
          end_col = end_col,
          hl_group = item.group,
        })
      end
    end
  end
end

local function close_card(card)
  if card.window and vim.api.nvim_win_is_valid(card.window) then
    pcall(vim.api.nvim_win_close, card.window, true)
  end
  if card.buffer and vim.api.nvim_buf_is_valid(card.buffer) then
    pcall(vim.api.nvim_buf_delete, card.buffer, { force = true })
  end
  card.window = nil
  card.buffer = nil
end

local function card_window_highlight(card)
  local group = card.selected_group or "ProudCard"
  return table.concat({
    "Normal:" .. group,
    "NormalNC:" .. group,
    "NormalFloat:" .. group,
    "FloatBorder:ProudCardBorder",
    "EndOfBuffer:" .. group,
    "Cursor:ProudCursorHidden",
    "lCursor:ProudCursorHidden",
    "CursorIM:ProudCursorHidden",
    "StatusLine:ProudPanel",
    "StatusLineNC:ProudPanel",
  }, ",")
end

local function card_border(top_visible, bottom_visible)
  return {
    top_visible and "╭" or "",
    top_visible and "─" or "",
    top_visible and "╮" or "",
    "│",
    bottom_visible and "╯" or "",
    bottom_visible and "─" or "",
    bottom_visible and "╰" or "",
    "│",
  }
end

function M.create(options)
  options = options or {}
  instance_sequence = instance_sequence + 1
  local state = {
    host_window = options.host_window,
    cards = {},
    specs = {},
    selected_id = options.selected_id,
    group = vim.api.nvim_create_augroup("ProudConversationCards" .. instance_sequence, { clear = true }),
  }
  local function refresh()
    vim.schedule(function()
      if state.host_window and vim.api.nvim_win_is_valid(state.host_window) then
        M.sync(state, state.specs)
      end
    end)
  end
  vim.api.nvim_create_autocmd({ "WinScrolled", "WinResized" }, {
    group = state.group,
    callback = refresh,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = state.group,
    pattern = tostring(options.host_window or ""),
    callback = function()
      state.host_window = nil
      M.close(state)
    end,
  })
  return state
end

function M.sync(state, specs)
  if not state then
    return 0
  end
  state.specs = specs or {}
  local host_window = state.host_window
  if not host_window or not vim.api.nvim_win_is_valid(host_window) then
    M.close(state)
    return 0
  end
  local topline = vim.api.nvim_win_call(host_window, function()
    return vim.fn.winsaveview().topline
  end)
  local host_height = vim.api.nvim_win_get_height(host_window)
  local desired = {}
  for _, spec in ipairs(state.specs) do
    desired[spec.id] = spec
  end
  for id, card in pairs(state.cards) do
    if not desired[id] then
      close_card(card)
      state.cards[id] = nil
    end
  end
  local visible = 0
  for _, spec in ipairs(state.specs) do
    local top = spec.row - topline
    local clipped = clip_card(spec, top, host_height)
    local card = state.cards[spec.id]
    if not clipped then
      if card then
        close_card(card)
        state.cards[spec.id] = nil
      end
    else
      if not card then
        local buffer = vim.api.nvim_create_buf(false, true)
        vim.bo[buffer].buftype = "nofile"
        vim.bo[buffer].bufhidden = "wipe"
        vim.bo[buffer].swapfile = false
        vim.api.nvim_buf_set_name(buffer, "proud://conversation-card/" .. spec.id)
        card = { buffer = buffer, signature = "" }
        state.cards[spec.id] = card
      end
      card.spec = spec
      card.visible = clipped
      card.selected_group = state.selected_id == spec.id and "ProudCardSelected" or spec.selected_group
      local signature = table.concat({
        table.concat(clipped.lines, "\0"),
        tostring(clipped.row),
        tostring(clipped.height),
        tostring(clipped.top_visible),
        tostring(clipped.bottom_visible),
      }, "\0")
      if card.signature ~= signature then
        set_card_lines(card)
        card.signature = signature
      end
      card.placement = {
        relative = "win",
        win = host_window,
        row = clipped.row,
        col = spec.col,
        width = spec.width,
        height = clipped.height,
        border = card_border(clipped.top_visible, clipped.bottom_visible),
        focusable = false,
        zindex = 42,
      }
      if not card.window or not vim.api.nvim_win_is_valid(card.window) then
        card.float = ui.float.create(card.buffer, {
          placement = function()
            return card.placement
          end,
        })
        card.window = card.float.window
      else
        card.float.reposition()
      end
      vim.wo[card.window].winhighlight = card_window_highlight(card)
      vim.wo[card.window].wrap = false
      vim.wo[card.window].cursorline = false
      vim.wo[card.window].number = false
      vim.wo[card.window].relativenumber = false
      vim.wo[card.window].signcolumn = "no"
      visible = visible + 1
    end
  end
  return visible
end

function M.select(state, id)
  if not state then
    return false
  end
  state.selected_id = id
  M.sync(state, state.specs)
  return true
end

function M.close(state)
  if not state then
    return
  end
  for _, card in pairs(state.cards or {}) do
    close_card(card)
  end
  state.cards = {}
  if state.group then
    pcall(vim.api.nvim_del_augroup_by_id, state.group)
    state.group = nil
  end
end

return M
