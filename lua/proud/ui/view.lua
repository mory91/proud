-- Helpers for building views ({ lines, highlights }) in feature renderers.
--
-- Highlights are recorded as text is appended, so their columns are exact.
-- Use line() for chunk lists, spans() or open/add/close where per-render
-- tables matter, and wrapped() for text that wraps to a pane width.
local ui_text = require("proud.ui.text")

local M = {}

local View = {}
View.__index = View

-- Creates a view builder. options.width, when set, fits every line to that
-- display width (padding or clipping) and clips its highlights to match.
function M.new(options)
  options = options or {}
  return setmetatable({
    lines = {},
    highlights = {},
    width = options.width,
    parts = {},
    part_count = 0,
    col = 0,
  }, View)
end

-- Starts a line; returns its 0-based row. Pair with add() and close() in
-- hot loops to avoid allocating chunk tables.
function View:open()
  assert(self.open_row == nil, "view line already open")
  self.open_row = #self.lines
  self.col = 0
  return self.open_row
end

-- Appends text to the open line, highlighted with `group` when given.
function View:add(text, group)
  text = text == nil and "" or tostring(text)
  if text == "" then
    return self
  end
  local count = self.part_count + 1
  self.parts[count] = text
  self.part_count = count
  if group then
    local highlights = self.highlights
    local n = #highlights
    if n >= 4
      and highlights[n - 3] == self.open_row
      and highlights[n - 1] == self.col
      and highlights[n] == group
    then
      -- Continues the previous highlight: extend it instead of adding one.
      highlights[n - 1] = self.col + #text
    else
      highlights[n + 1] = self.open_row
      highlights[n + 2] = self.col
      highlights[n + 3] = self.col + #text
      highlights[n + 4] = group
    end
  end
  self.col = self.col + #text
  return self
end

-- Clamps this row's highlights (always the newest ones) to the line length.
local function clip_row(highlights, row, length)
  local index = #highlights - 3
  while index >= 1 and highlights[index] == row do
    if highlights[index + 1] > length then
      highlights[index + 1] = length
    end
    if highlights[index + 2] > length then
      highlights[index + 2] = length
    end
    index = index - 4
  end
end

-- Highlights the whole open line with `group`. It is recorded now, so
-- highlights added afterwards on the same row draw on top of it.
function View:fill(group)
  local row = assert(self.open_row, "no view line open")
  return self:mark(row, 0, math.huge, group)
end

-- Finishes the open line; returns its 0-based row. Highlights on the row
-- are clipped to the final line length.
function View:close()
  local row = assert(self.open_row, "no view line open")
  local count = self.part_count
  local parts = self.parts
  local line
  if count == 0 then
    line = ""
  elseif count == 1 then
    -- Single chunk: reuse the string itself (no copy for constant text).
    line = parts[1]
    parts[1] = nil
  else
    line = table.concat(parts, "", 1, count)
    for index = 1, count do
      parts[index] = nil
    end
  end
  self.part_count = 0
  if self.width then
    line = ui_text.fit(line, self.width)
  end
  clip_row(self.highlights, row, #line)
  self.lines[row + 1] = line
  self.open_row = nil
  return row
end

-- Appends one line made of chunks: plain strings or { text, group }.
-- Returns its 0-based row.
function View:line(...)
  self:open()
  for index = 1, select("#", ...) do
    local chunk = select(index, ...)
    if type(chunk) == "table" then
      self:add(chunk[1], chunk[2])
    else
      self:add(chunk)
    end
  end
  return self:close()
end

-- Allocation-free alternative to line(): alternating text and group
-- arguments (group may be nil for plain text). Returns the row.
--   v:spans("The token is ", nil, "hidden", "ProudSuccessText", ".")
function View:spans(...)
  self:open()
  local count = select("#", ...)
  for index = 1, count, 2 do
    local text, group = select(index, ...)
    self:add(text, group)
  end
  return self:close()
end

-- Reusable scratch array for emit(): text/group pairs, one row at a time.
function View:segments()
  local seg = self.seg
  if not seg then
    seg = {}
    self.seg = seg
  end
  return seg
end

-- Appends one row from seg[1..count] (text, group, text, group, ...),
-- optionally filled with `fill` underneath. Texts must be strings. The
-- loop appends inline (no add() call) to keep compiled code small.
function View:emit(seg, count, fill)
  assert(self.open_row == nil, "view line already open")
  local row = #self.lines
  local highlights = self.highlights
  local n = #highlights
  if fill then
    highlights[n + 1] = row
    highlights[n + 2] = 0
    highlights[n + 3] = math.huge
    highlights[n + 4] = fill
    n = n + 4
  end
  local parts = self.parts
  local part_count = 0
  local col = 0
  for index = 1, count, 2 do
    local text, group = seg[index], seg[index + 1]
    local length = #text
    if length > 0 then
      part_count = part_count + 1
      parts[part_count] = text
      if group then
        if n >= 4 and highlights[n - 3] == row and highlights[n - 1] == col and highlights[n] == group then
          highlights[n - 1] = col + length
        else
          highlights[n + 1] = row
          highlights[n + 2] = col
          highlights[n + 3] = col + length
          highlights[n + 4] = group
          n = n + 4
        end
      end
      col = col + length
    end
  end
  local line
  if part_count == 1 then
    line = parts[1]
  else
    line = table.concat(parts, "", 1, part_count)
  end
  for index = 1, part_count do
    parts[index] = nil
  end
  if self.width then
    line = ui_text.fit(line, self.width)
  end
  if fill or #line < col then
    clip_row(highlights, row, #line)
  end
  self.lines[row + 1] = line
  return row
end

function View:blank()
  return self:line()
end

-- Appends a horizontal rule `width` cells wide (default: the view width).
function View:rule(group, width)
  width = width or self.width
  assert(width, "rule needs a width")
  return self:line({ string.rep("─", width), group })
end

-- Highlights an explicit byte range on an existing row.
function View:mark(row, start_col, end_col, group)
  local highlights = self.highlights
  local n = #highlights
  highlights[n + 1] = row
  highlights[n + 2] = start_col
  highlights[n + 3] = end_col
  highlights[n + 4] = group
  return self
end

-- Number of lines so far, i.e. the row the next line will get.
function View:row()
  return #self.lines
end

-- Adds virtual text after the end of `row` (not part of the buffer text).
-- Stored flat as row, text, group triples.
function View:eol(row, text, group)
  local virtual = self.virtual
  if not virtual then
    virtual = {}
    self.virtual = virtual
  end
  local n = #virtual
  virtual[n + 1] = row
  virtual[n + 2] = text
  virtual[n + 3] = group or "ProudMuted"
  return self
end

function View:build()
  assert(self.open_row == nil, "view line still open")
  return {
    lines = self.lines,
    highlights = self.highlights,
    highlight_format = "flat",
    virtual = self.virtual,
  }
end

-- Group of the range covering byte `position` of the source, or nil.
local function group_at(ranges, position)
  for index = 1, #ranges, 3 do
    if ranges[index] <= position and position < ranges[index + 1] then
      return ranges[index + 2]
    end
  end
end

-- Appends source bytes [start, stop) split by highlight ranges, spending at
-- most `budget` bytes. Returns the remaining budget.
local function add_slice(v, source, ranges, start, stop, budget)
  stop = math.min(stop, start + budget)
  local position = start
  while position < stop do
    local group = group_at(ranges, position)
    local next_stop = stop
    for index = 1, #ranges, 3 do
      local edge_a, edge_b = ranges[index], ranges[index + 1]
      if edge_a > position and edge_a < next_stop then
        next_stop = edge_a
      end
      if edge_b > position and edge_b < next_stop then
        next_stop = edge_b
      end
    end
    v:add(source:sub(position + 1, next_stop), group)
    position = next_stop
  end
  return budget - (stop - start)
end

-- Appends chunks wrapped exactly like ui.content_lines: options.width is
-- the full width including options.padding on both sides, and wrapping
-- follows options.wrap or Neovim's 'wrap'. Each chunk's highlight follows
-- its text onto every wrapped line; a joining space is highlighted when the
-- whitespace it replaces was inside one highlighted chunk. Returns the
-- first and last rows written.
function View:wrapped(chunks, options)
  options = options or {}
  local width = math.max(1, math.floor(options.width or self.width or 80))
  local padding = math.max(0, math.floor(options.padding or 0))
  padding = math.min(padding, math.floor((width - 1) / 2))
  local inner_width = width - padding * 2
  local margin = string.rep(" ", padding)
  local wrap_enabled = ui_text.should_wrap(options)

  local parts, ranges, position = {}, {}, 0
  for _, chunk in ipairs(chunks) do
    local text, group
    if type(chunk) == "table" then
      text, group = tostring(chunk[1] or ""), chunk[2]
    else
      text = tostring(chunk or "")
    end
    parts[#parts + 1] = text
    if group and text ~= "" then
      ranges[#ranges + 1] = position
      ranges[#ranges + 1] = position + #text
      ranges[#ranges + 1] = group
    end
    position = position + #text
  end
  local source = table.concat(parts)

  local first_row
  local last_row
  for _, line_ranges in ipairs(ui_text.wrap_pieces(source, inner_width, { wrap = wrap_enabled })) do
    local content = ui_text.piece_text(source, line_ranges)
    local budget = #content
    local pad = 0
    if wrap_enabled then
      local clipped = ui_text.clip(content, inner_width)
      budget = #clipped
      pad = inner_width - ui_text.display_width(clipped)
    end
    local row = self:open()
    first_row = first_row or row
    last_row = row
    self:add(margin)
    for index = 1, #line_ranges, 2 do
      if index > 1 and budget > 0 then
        local before, after = line_ranges[index - 1], line_ranges[index]
        local group = group_at(ranges, before - 1)
        if group == nil or group ~= group_at(ranges, after) or group_at(ranges, before) ~= group then
          group = nil
        end
        self:add(" ", group)
        budget = budget - 1
      end
      budget = add_slice(self, source, ranges, line_ranges[index], line_ranges[index + 1], math.max(0, budget))
    end
    self:add(string.rep(" ", pad) .. margin)
    self:close()
  end
  return first_row, last_row
end

-- Spaces needed after `value` to fill `width` display cells (for %-Ns-style
-- columns built from chunks).
function M.padding(value, width)
  return string.rep(" ", math.max(0, width - ui_text.display_width(tostring(value or ""))))
end

return M
