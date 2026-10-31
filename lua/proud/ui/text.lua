local M = {}

function M.display_width(value)
  if not value:find("[\128-\255]") then
    return #value
  end
  return vim.fn.strdisplaywidth(value)
end

function M.fit(value, width)
  value = tostring(value or "")
  width = math.max(1, math.floor(width))
  local value_width = M.display_width(value)
  if value_width <= width then
    return value .. string.rep(" ", width - value_width)
  end
  if not value:find("[\128-\255]") then
    return value:sub(1, width)
  end

  local clipped = vim.fn.strcharpart(value, 0, width)
  while M.display_width(clipped) > width do
    clipped = vim.fn.strcharpart(clipped, 0, math.max(0, vim.fn.strchars(clipped) - 1))
  end
  return clipped .. string.rep(" ", width - M.display_width(clipped))
end

local function should_wrap(options)
  if options and options.wrap ~= nil then
    return options.wrap == true
  end
  return vim.go.wrap == true
end

function M.wrap_text(value, width, options)
  options = options or {}
  width = math.max(1, math.floor(width or 80))
  value = tostring(value or "")
  local sources = { value }
  if value:find("\n", 1, true) then
    sources = vim.split(value, "\n", { plain = true })
  end
  if not should_wrap(options) then
    return sources
  end
  local lines = {}
  for _, source in ipairs(sources) do
    if source == "" or M.display_width(source) <= width then
      table.insert(lines, source)
    else
      source = source:gsub("%s+", " ")
      local current = ""
      for word in source:gmatch("%S+") do
        while M.display_width(word) > width do
          local cut = 0
          for index = 1, vim.fn.strchars(word) do
            local candidate = vim.fn.strcharpart(word, 0, index)
            if M.display_width(candidate) > width then
              break
            end
            cut = index
          end
          if cut == 0 then
            cut = 1
          end
          local piece = vim.fn.strcharpart(word, 0, cut)
          if current ~= "" then
            table.insert(lines, current)
            current = ""
          end
          table.insert(lines, piece)
          word = vim.fn.strcharpart(word, cut)
        end
        local candidate = current == "" and word or current .. " " .. word
        if M.display_width(candidate) > width and current ~= "" then
          table.insert(lines, current)
          current = word
        else
          current = candidate
        end
      end
      table.insert(lines, current)
    end
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
