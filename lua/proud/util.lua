local M = {}

function M.deep_merge(base, override)
  local result = {}
  for key, value in pairs(base or {}) do
    result[key] = value
  end
  for key, value in pairs(override or {}) do
    if type(value) == "table" and type(result[key]) == "table" then
      result[key] = M.deep_merge(result[key], value)
    else
      result[key] = value
    end
  end
  return result
end

function M.trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.split(value, separator)
  local parts = {}
  separator = separator or "%s+"
  for part in value:gmatch("([^" .. separator .. "]+)") do
    table.insert(parts, part)
  end
  return parts
end

function M.contains(values, needle)
  for _, value in ipairs(values or {}) do
    if value == needle then
      return true
    end
  end
  return false
end

function M.clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function M.copy(value)
  if type(value) ~= "table" then
    return value
  end
  local result = {}
  for key, item in pairs(value) do
    result[key] = M.copy(item)
  end
  return result
end

local function days_from_civil(year, month, day)
  year = year - (month <= 2 and 1 or 0)
  local era = math.floor(year / 400)
  local year_of_era = year - era * 400
  local shifted_month = month + (month > 2 and -3 or 9)
  local day_of_year = math.floor((153 * shifted_month + 2) / 5) + day - 1
  local day_of_era = year_of_era * 365
    + math.floor(year_of_era / 4)
    - math.floor(year_of_era / 100)
    + day_of_year
  return era * 146097 + day_of_era - 719468
end

function M.parse_iso8601(value)
  local text = type(value) == "string" and value or tostring(value or "")
  local date, time, zone = text:match("^(%d%d%d%d%-%d%d%-%d%d)T(%d%d:%d%d:%d%d)%.?%d*(.*)$")
  if not date then
    return nil
  end
  local year, month, day = date:match("^(%d+)-(%d+)-(%d+)$")
  local hour, minute, second = time:match("^(%d+):(%d+):(%d+)$")
  year, month, day = tonumber(year), tonumber(month), tonumber(day)
  hour, minute, second = tonumber(hour), tonumber(minute), tonumber(second)
  if not year
    or month < 1
    or month > 12
    or day < 1
    or day > 31
    or hour > 23
    or minute > 59
    or second > 60
  then
    return nil
  end
  zone = M.trim(zone)
  local offset = 0
  if zone ~= "" and zone ~= "Z" and zone ~= "z" then
    local sign, offset_hour, offset_minute = zone:match("^([+-])(%d%d):?(%d%d)$")
    if not sign then
      return nil
    end
    offset = (tonumber(offset_hour) * 60 + tonumber(offset_minute)) * 60
    if sign == "-" then
      offset = -offset
    end
  end
  local timestamp = days_from_civil(year, month, day) * 86400
    + hour * 3600
    + minute * 60
    + math.min(second, 59)
    - offset
  return timestamp
end

function M.relative_time(value, options)
  options = options or {}
  if value == nil then
    return ""
  end
  local text = type(value) == "string" and value or tostring(value)
  if text:match("^%s") or text:match("%s$") then
    text = M.trim(text)
  end
  if text:match("^%d+mo$") or text:match("^%d+[mhdwy]$") or text == "now" then
    return text
  end
  local timestamp = tonumber(value) or M.parse_iso8601(text)
  if not timestamp then
    return text
  end
  local now = tonumber(options.now) or os.time()
  local elapsed = math.max(0, math.floor(now - timestamp))
  local minute = 60
  local hour = 60 * minute
  local day = 24 * hour
  local week = 7 * day
  local month = 30 * day
  local year = 365 * day
  if elapsed < minute then
    return "now"
  elseif elapsed < hour then
    return math.floor(elapsed / minute) .. "m"
  elseif elapsed < day then
    return math.floor(elapsed / hour) .. "h"
  elseif elapsed < week then
    return math.floor(elapsed / day) .. "d"
  elseif elapsed < month then
    return math.floor(elapsed / week) .. "w"
  elseif elapsed < year then
    return math.floor(elapsed / month) .. "mo"
  end
  return math.floor(elapsed / year) .. "y"
end

function M.root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":h:h:h")
end

function M.path(...)
  return table.concat({ ... }, "/")
end

return M
