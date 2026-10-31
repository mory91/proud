local util = require("proud.util")

local M = {}
local cache = {}

function M.load(name)
  if cache[name] then
    return cache[name]
  end
  local path = util.path(util.root(), "features", name, "feature.lua")
  local chunk, load_error = loadfile(path)
  if not chunk then
    error(("Unable to load feature %s: %s"):format(name, load_error))
  end
  cache[name] = chunk()
  return cache[name]
end

function M.clear()
  cache = {}
end

return M
