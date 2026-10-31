local M = {}

local function new_timer()
  return (vim.uv or vim.loop).new_timer()
end

function M.new(delay, callback)
  delay = math.max(0, math.floor(tonumber(delay) or 0))
  callback = callback or function() end
  local timer
  local generation = 0
  local arguments
  local active = false
  local disposed = false

  local function stop()
    active = false
    if timer then
      timer:stop()
    end
  end

  local function schedule(_, ...)
    if disposed then
      return
    end
    generation = generation + 1
    arguments = { ... }
    stop()
    timer = timer or new_timer()
    active = true
    timer:start(delay, 0, function()
      local scheduled_generation = generation
      local scheduled_arguments = arguments
      stop()
      vim.schedule(function()
        if scheduled_generation == generation then
          callback(unpack(scheduled_arguments))
        end
      end)
    end)
  end

  return {
    schedule = schedule,
    cancel = function()
      generation = generation + 1
      arguments = nil
      stop()
    end,
    dispose = function()
      generation = generation + 1
      arguments = nil
      stop()
      if timer then
        timer:close()
        timer = nil
      end
      disposed = true
    end,
    pending = function()
      return active and not disposed
    end,
  }
end

return M
