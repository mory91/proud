-- Helpers for building views ({ lines, highlights }) in feature renderers.
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

return M
