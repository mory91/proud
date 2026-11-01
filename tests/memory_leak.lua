local session = require("proud.session")

local function valid_buffers()
  local count = 0
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buffer) then
      count = count + 1
    end
  end
  return count
end

local function collect()
  if jit and jit.flush then
    jit.flush()
  end
  collectgarbage("collect")
  collectgarbage("collect")
  return {
    heap_kb = collectgarbage("count"),
    buffers = valid_buffers(),
    windows = #vim.api.nvim_list_wins(),
  }
end

local function settle()
  vim.wait(15, function()
    return false
  end, 5)
end

local function close_with_key(key)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "x", false)
  settle()
end

local scenarios = {
  credentials = {
    open = function()
      local feature = require("proud.loader").load("github_credentials")
      local state = feature.create({
        token_path = vim.fn.tempname(),
        credential = false,
      })
      local _, window = feature.open(state)
      return { feature = feature, state = state, window = window }
    end,
    close = function(handle)
      close_with_key("<Esc>")
      assert(not vim.api.nvim_win_is_valid(handle.window), "credential screen did not close")
    end,
  },
  browser = {
    open = function()
      session.demo("browser")
      return session.current
    end,
    close = function()
      close_with_key("q")
    end,
  },
  overview = {
    open = function()
      session.demo("overview")
      return session.current
    end,
    close = function()
      close_with_key("q")
    end,
  },
  single = {
    -- The editable diff shows real files, where q means macro recording,
    -- so the scene is closed through its own close function after the
    -- checkout has finished.
    open = function()
      session.demo("single")
      local state = session.current.state
      vim.wait(15000, function()
        return state.status ~= "loading"
          and (state.status ~= "ready" or next(state.scene.handles) ~= nil)
      end, 10)
      return session.current
    end,
    close = function(handle)
      handle.state.close()
      vim.wait(1000, function()
        return handle.state.scene.lifecycle.closed()
      end, 10)
    end,
  },
  compare = {
    open = function()
      session.demo("compare")
      return session.current
    end,
    close = function()
      close_with_key("q")
    end,
  },
  help = {
    open = function()
      session.demo("help")
      return session.help
    end,
    close = function()
      close_with_key("q")
    end,
  },
  review = {
    open = function()
      session.demo("review")
      return session.current
    end,
    close = function()
      close_with_key("q")
    end,
  },
}

local function median(values)
  local sorted = vim.deepcopy(values)
  table.sort(sorted)
  local middle = math.floor((#sorted + 1) / 2)
  if #sorted % 2 == 0 then
    return (sorted[middle] + sorted[middle + 1]) / 2
  end
  return sorted[middle]
end

local function robust_growth(samples)
  local slopes = {}
  for left = 1, #samples do
    for right = left + 1, #samples do
      table.insert(slopes, (samples[right] - samples[left]) / (right - left))
    end
  end
  return median(slopes) * math.max(1, #samples - 1)
end

local function run(screen, options)
  options = options or {}
  local scenario = scenarios[screen]
  assert(scenario, "unknown memory-leak screen: " .. tostring(screen))
  local warmup_cycles = math.max(3, tonumber(options.warmup_cycles) or 8)
  local measured_cycles = math.max(4, tonumber(options.measured_cycles) or 12)
  local max_growth_kb = math.max(1, tonumber(options.max_growth_kb) or 64)

  local function cycle()
    local handle = scenario.open()
    settle()
    scenario.close(handle)
    settle()
  end

  for _ = 1, warmup_cycles do
    cycle()
  end
  local function collected_sample()
    for _ = 1, 8 do
      collect()
    end
    return collect()
  end
  local baseline = collected_sample()
  local samples = {}
  for _ = 1, measured_cycles do
    cycle()
    local snapshot = collected_sample()
    table.insert(samples, snapshot.heap_kb)
  end
  local final = collected_sample()
  local growth_kb = robust_growth(samples)
  local trend_kb = growth_kb
  local resources_stable = final.buffers == baseline.buffers and final.windows == baseline.windows
  local ok = growth_kb <= max_growth_kb and trend_kb <= max_growth_kb and resources_stable
  return {
    ok = ok,
    screen = screen,
    baseline_heap_kb = baseline.heap_kb,
    final_heap_kb = final.heap_kb,
    heap_samples_kb = samples,
    growth_kb = growth_kb,
    trend_kb = trend_kb,
    baseline_buffers = baseline.buffers,
    final_buffers = final.buffers,
    baseline_windows = baseline.windows,
    final_windows = final.windows,
    warmup_cycles = warmup_cycles,
    measured_cycles = measured_cycles,
    max_growth_kb = max_growth_kb,
    resources_stable = resources_stable,
  }
end

return run
