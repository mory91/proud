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

function M.render(sections, spacing)
  local normalized_sections = M.normalize_sections(sections)
  local normalized_spacing = M.normalize_spacing(spacing)
  local line = ""
  local highlights = {}
  for section_index, section in ipairs(normalized_sections) do
    if section_index > 1 then
      local gap = normalized_spacing[section_index - 1]
        or normalized_spacing[#normalized_spacing]
        or 0
      line = line .. string.rep(" ", gap)
    end
    for _, part in ipairs(section.parts) do
      local start_col = #line
      line = line .. part.text
      if part.group and part.text ~= "" then
        table.insert(highlights, {
          line = 0,
          start_col = start_col,
          end_col = #line,
          group = part.group,
        })
      end
    end
  end
  return line, highlights
end

return M
