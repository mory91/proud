local M = {
  assertions = 0,
  failures = {},
}

local function stringify(value)
  return vim.inspect(value):gsub("\n", " ")
end

function M.truthy(value, message)
  M.assertions = M.assertions + 1
  if not value then
    table.insert(M.failures, message or "expected truthy value")
  end
end

function M.eq(expected, actual, message)
  M.assertions = M.assertions + 1
  if not vim.deep_equal(expected, actual) then
    table.insert(M.failures, (message or "values differ") .. ": expected " .. stringify(expected) .. ", got " .. stringify(actual))
  end
end

function M.contains(haystack, needle, message)
  M.assertions = M.assertions + 1
  local found = false
  if type(haystack) == "table" then
    found = vim.tbl_contains(haystack, needle)
  else
    found = tostring(haystack):find(tostring(needle), 1, true) ~= nil
  end
  if not found then
    table.insert(M.failures, (message or "missing value") .. ": " .. tostring(needle))
  end
end

function M.matches(value, pattern, message)
  M.assertions = M.assertions + 1
  if not tostring(value):match(pattern) then
    table.insert(M.failures, (message or "pattern did not match") .. ": " .. tostring(value))
  end
end

function M.highlighted(view, needle, group, message)
  M.assertions = M.assertions + 1
  local found = false
  for row, line in ipairs(view.lines or {}) do
    local start_col = tostring(line):find(tostring(needle), 1, true)
    if start_col then
      start_col = start_col - 1
      if view.highlight_format == "flat" then
        for index = 1, #(view.highlights or {}), 4 do
          if view.highlights[index] == row - 1
            and view.highlights[index + 3] == group
            and view.highlights[index + 1] <= start_col
            and view.highlights[index + 2] > start_col
          then
            found = true
            break
          end
        end
      else
        for _, item in ipairs(view.highlights or {}) do
          local item_line = item.line or item[1]
          local item_start = item.start_col or item[2] or 0
          local item_end = item.end_col or item[3] or #line
          local item_group = item.group or item[4]
          if item_line == row - 1
            and item_group == group
            and item_start <= start_col
            and item_end > start_col
          then
            found = true
            break
          end
        end
      end
    end
    if found then
      break
    end
  end
  if not found then
    table.insert(M.failures, (message or "missing semantic highlight") .. ": " .. tostring(needle) .. " as " .. tostring(group))
  end
end

function M.finish()
  if #M.failures > 0 then
    for _, failure in ipairs(M.failures) do
      io.stderr:write("FAIL " .. failure .. "\n")
    end
    io.stderr:write(("%d assertions, %d failures\n"):format(M.assertions, #M.failures))
    os.exit(1)
  end
  print(("PASS %d assertions"):format(M.assertions))
  os.exit(0)
end

return M
