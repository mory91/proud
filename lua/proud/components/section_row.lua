local M = {}

M.max_sections = 5

local function single_line(value)
  value = tostring(value or "")
  if not value:find("[\r\n]") then
    return value
  end
  return (value:gsub("\r\n", "\n"):gsub("[\r\n]", " "))
end

local function normalize_part(part)
  if type(part) ~= "table" then
    part = { text = part }
  end
  return {
    text = single_line(part.text),
    group = part.group,
  }
end

local function normalize_section(section)
  if type(section) ~= "table" then
    section = { text = section }
  end
  local normalized = {
    group = section.group,
  }
  if section.parts then
    normalized.parts = {}
    for _, part in ipairs(section.parts) do
      table.insert(normalized.parts, normalize_part(part))
    end
  else
    normalized.parts = { normalize_part(section) }
  end
  if #normalized.parts == 1 then
    normalized.text = normalized.parts[1].text
  end
  return normalized
end

function M.normalize_sections(sections)
  if type(sections) ~= "table" or #sections == 0 then
    error("section row requires at least one section")
  end
  if #sections > M.max_sections then
    error(("section row supports at most %d sections"):format(M.max_sections))
  end
  local normalized = {}
  for _, section in ipairs(sections) do
    table.insert(normalized, normalize_section(section))
  end
  return normalized
end

function M.normalize_spacing(spacing)
  if spacing == nil then
    return { 1 }
  end
  if type(spacing) == "number" then
    if spacing < 0 or spacing % 1 ~= 0 then
      error("section spacing must be a non-negative integer")
    end
    return { spacing }
  end
  if type(spacing) ~= "table" or #spacing == 0 then
    error("section spacing must be a number or a non-empty list")
  end
  local normalized = {}
  for _, value in ipairs(spacing) do
    if type(value) ~= "number" or value < 0 or value % 1 ~= 0 then
      error("section spacing values must be non-negative integers")
    end
    table.insert(normalized, value)
  end
  return normalized
end

-- Gap before section `index` (2-based) for a spacing value that is a
-- number, a list (last entry repeats), or nil (one space).
local function gap_before(spacing, index)
  if type(spacing) == "number" then
    return spacing
  end
  if type(spacing) == "table" then
    return spacing[index - 1] or spacing[#spacing] or 1
  end
  return 1
end

local gap_cache = {}
local function gap_text(count)
  local value = gap_cache[count]
  if not value then
    value = string.rep(" ", count)
    gap_cache[count] = value
  end
  return value
end

-- Appends already-normalized sections as text/group pairs to a
-- proud.ui.view segments array, starting after index `count`; returns the
-- new count. Shared by render() and the tree component, which emit() the
-- row in one call.
function M.append_segments(seg, count, sections, spacing)
  for section_index, section in ipairs(sections) do
    if section_index > 1 then
      seg[count + 1] = gap_text(gap_before(spacing, section_index))
      seg[count + 2] = false
      count = count + 2
    end
    for _, part in ipairs(section.parts) do
      seg[count + 1] = part.text
      seg[count + 2] = part.group or false
      count = count + 2
    end
  end
  return count
end

-- Renders one row; returns the line and keyed highlights.
function M.render(sections, spacing)
  local v = require("proud.ui.view").new()
  local seg = v:segments()
  v:emit(seg, M.append_segments(seg, 0, M.normalize_sections(sections), M.normalize_spacing(spacing)))
  local built = v:build()
  local highlights = {}
  for index = 1, #built.highlights, 4 do
    table.insert(highlights, {
      line = 0,
      start_col = built.highlights[index + 1],
      end_col = built.highlights[index + 2],
      group = built.highlights[index + 3],
    })
  end
  return built.lines[1], highlights
end

return M
