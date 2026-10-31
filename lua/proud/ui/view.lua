-- Helpers for building views ({ lines, highlights }) in feature renderers.
--
-- Prefer the builder (M.new): highlights are recorded as text is appended,
-- so their columns are exact. M.span searches finished text and is kept for
-- deliberate cases such as highlighting a word inside wrapped body text.
local ui_text = require("proud.ui.text")

local M = {}

-- Highlights the first occurrence of `needle` on 0-based `row` of `lines`.
-- `format` selects the highlight shape appended to `highlights`:
--   nil / "keyed": { line = r, start_col = s, end_col = e, group = g }
--   "tuple":       { r, s, e, g }
--   "flat":        r, s, e, g appended in place (highlight_format = "flat")
-- Returns true when the needle was found.
function M.span(lines, highlights, row, needle, group, format)
  if not needle or needle == "" then
    return false
  end
  local start_col = tostring(lines[row + 1] or ""):find(needle, 1, true)
  if not start_col then
    return false
  end
  start_col = start_col - 1
  local end_col = start_col + #needle
  if format == "flat" then
    local count = #highlights
    highlights[count + 1] = row
    highlights[count + 2] = start_col
    highlights[count + 3] = end_col
    highlights[count + 4] = group
  elseif format == "tuple" then
    highlights[#highlights + 1] = { row, start_col, end_col, group }
  else
    highlights[#highlights + 1] = { line = row, start_col = start_col, end_col = end_col, group = group }
  end
  return true
end

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
    highlights[n + 1] = self.open_row
    highlights[n + 2] = self.col
    highlights[n + 3] = self.col + #text
    highlights[n + 4] = group
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

-- Finishes the open line; returns its 0-based row.
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
    clip_row(self.highlights, row, #line)
  end
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

-- Highlights the first occurrence of `needle` on an existing row (search
-- based; prefer chunks). Returns true when found.
function View:find(row, needle, group)
  return M.span(self.lines, self.highlights, row, needle, group, "flat")
end

-- Number of lines so far, i.e. the row the next line will get.
function View:row()
  return #self.lines
end

function View:build()
  assert(self.open_row == nil, "view line still open")
  return { lines = self.lines, highlights = self.highlights, highlight_format = "flat" }
end

-- Spaces needed after `value` to fill `width` display cells (for %-Ns-style
-- columns built from chunks).
function M.padding(value, width)
  return string.rep(" ", math.max(0, width - ui_text.display_width(tostring(value or ""))))
end

return M
