local M = {}

function M.display_width(value)
  if not value:find("[\128-\255]") then
    return #value
  end
  return vim.fn.strdisplaywidth(value)
end

-- Longest prefix of `value` that fits in `width` display cells.
function M.clip(value, width)
  value = tostring(value or "")
  width = math.max(0, math.floor(width))
  if M.display_width(value) <= width then
    return value
  end
  if not value:find("[\128-\255]") then
    return value:sub(1, width)
  end
  local clipped = vim.fn.strcharpart(value, 0, width)
  while M.display_width(clipped) > width do
    clipped = vim.fn.strcharpart(clipped, 0, math.max(0, vim.fn.strchars(clipped) - 1))
  end
  return clipped
end

-- Pads or clips `value` to exactly `width` display cells.
function M.fit(value, width)
  value = tostring(value or "")
  width = math.max(1, math.floor(width))
  local clipped = M.clip(value, width)
  return clipped .. string.rep(" ", width - M.display_width(clipped))
end

function M.should_wrap(options)
  if options and options.wrap ~= nil then
    return options.wrap == true
  end
  return vim.go.wrap == true
end
local should_wrap = M.should_wrap

-- Wraps one source line (no newlines) starting at byte `base` of the full
-- value, appending output lines to `out`. Each output line is a flat list
-- of byte ranges { start1, stop1, start2, stop2, ... } (0-based start,
-- exclusive stop) into the full value; its text is those ranges joined by
-- single spaces. A line that already fits is one range, kept verbatim.
local function wrap_source(source, base, width, out)
  if source == "" or M.display_width(source) <= width then
    out[#out + 1] = { base, base + #source }
    return
  end
  local current
  local current_width = 0
  local init = 1
  while true do
    local first, last = source:find("%S+", init)
    if not first then
      break
    end
    init = last + 1
    local start = base + first - 1
    local word = source:sub(first, last)
    local word_width = M.display_width(word)
    while word_width > width do
      local cut = 0
      for index = 1, vim.fn.strchars(word) do
        if M.display_width(vim.fn.strcharpart(word, 0, index)) > width then
          break
        end
        cut = index
      end
      if cut == 0 then
        cut = 1
      end
      local piece = vim.fn.strcharpart(word, 0, cut)
      if current then
        out[#out + 1] = current
        current = nil
      end
      out[#out + 1] = { start, start + #piece }
      start = start + #piece
      word = vim.fn.strcharpart(word, cut)
      word_width = M.display_width(word)
    end
    if word == "" then
      -- The split consumed the whole word: nothing left to place.
    elseif not current then
      current = { start, start + #word }
      current_width = word_width
    elseif current_width + 1 + word_width > width then
      out[#out + 1] = current
      current = { start, start + #word }
      current_width = word_width
    else
      current[#current + 1] = start
      current[#current + 1] = start + #word
      current_width = current_width + 1 + word_width
    end
  end
  out[#out + 1] = current or {}
end

-- Positional core of wrap_text: returns output lines as byte ranges into
-- `value` (see wrap_source). Follows the same rules and the 'wrap' option.
function M.wrap_pieces(value, width, options)
  width = math.max(1, math.floor(width or 80))
  value = tostring(value or "")
  local wrap_enabled = should_wrap(options)
  local out = {}
  local base = 0
  while true do
    local newline = value:find("\n", base + 1, true)
    local stop = newline and newline - 1 or #value
    local source = value:sub(base + 1, stop)
    if wrap_enabled then
      wrap_source(source, base, width, out)
    else
      out[#out + 1] = { base, stop }
    end
    if not newline then
      break
    end
    base = newline
  end
  return out
end

-- Text of one wrap_pieces line.
function M.piece_text(value, ranges)
  if #ranges == 2 then
    return value:sub(ranges[1] + 1, ranges[2])
  end
  local parts = {}
  for index = 1, #ranges, 2 do
    parts[#parts + 1] = value:sub(ranges[index] + 1, ranges[index + 1])
  end
  return table.concat(parts, " ")
end

function M.wrap_text(value, width, options)
  value = tostring(value or "")
  local lines = {}
  for index, ranges in ipairs(M.wrap_pieces(value, width, options)) do
    lines[index] = M.piece_text(value, ranges)
  end
  return lines
end

function M.content_lines(value, options)
  options = options or {}
  local width = math.max(1, math.floor(options.width or 80))
  local padding = math.max(0, math.floor(options.padding or 0))
  padding = math.min(padding, math.floor((width - 1) / 2))
  local inner_width = width - padding * 2
  local prefix = string.rep(" ", padding)
  local suffix = string.rep(" ", padding)
  local result = {}
  local wrap_enabled = should_wrap(options)
  for _, line in ipairs(M.wrap_text(value, inner_width, { wrap = wrap_enabled })) do
    local content = wrap_enabled and M.fit(line, inner_width) or line
    table.insert(result, prefix .. content .. suffix)
  end
  return result
end

return M
