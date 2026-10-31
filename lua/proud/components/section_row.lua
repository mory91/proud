local M = {}

M.max_sections = 5

local function single_line(value)
  return (tostring(value or ""):gsub("\r\n", "\n"):gsub("[\r\n]", " "))
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

-- Appends already-normalized sections to a row being built in plain
-- arrays: their text goes into `parts` after index `part_count`, and their
-- highlights go into the flat `highlights` array for `row`, starting at
-- byte column `col`. Returns the new part_count and col. Shared by
-- render() and the tree component's hot loop (no allocation per part).
function M.append_flat(parts, part_count, highlights, row, col, sections, spacing)
  for section_index, section in ipairs(sections) do
    if section_index > 1 then
      local gap = gap_text(gap_before(spacing, section_index))
      part_count = part_count + 1
      parts[part_count] = gap
      col = col + #gap
    end
    for _, part in ipairs(section.parts) do
      local text = part.text
      part_count = part_count + 1
      parts[part_count] = text
      if part.group and text ~= "" then
        local n = #highlights
        highlights[n + 1] = row
        highlights[n + 2] = col
        highlights[n + 3] = col + #text
        highlights[n + 4] = part.group
      end
      col = col + #text
    end
  end
  return part_count, col
end

-- Renders one row; returns the line and keyed highlights.
function M.render(sections, spacing)
  local parts, flat = {}, {}
  local count = M.append_flat(parts, 0, flat, 0, 0, M.normalize_sections(sections), M.normalize_spacing(spacing))
  local highlights = {}
  for index = 1, #flat, 4 do
    table.insert(highlights, {
      line = 0,
      start_col = flat[index + 1],
      end_col = flat[index + 2],
      group = flat[index + 3],
    })
  end
  return table.concat(parts, "", 1, count), highlights
end

return M
