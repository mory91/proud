local M = {}

function M.new(options)
  options = options or {}
  local cache = {
    max_items = options.max_items or 128,
    values = {},
    order = {},
  }

  function cache:get(key)
    local item = self.values[key]
    if not item then
      return nil
    end
    for index, value in ipairs(self.order) do
      if value == key then
        table.remove(self.order, index)
        break
      end
    end
    table.insert(self.order, key)
    return item
  end

  function cache:set(key, value)
    if not self.values[key] then
      table.insert(self.order, key)
    end
    self.values[key] = value
    while #self.order > self.max_items do
      local evicted = table.remove(self.order, 1)
      self.values[evicted] = nil
    end
    return value
  end

  function cache:clear()
    self.values = {}
    self.order = {}
  end

  return cache
end

return M
