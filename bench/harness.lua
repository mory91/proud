local uv = vim.uv or vim.loop

local M = {}

local function percentile(values, fraction)
  local sorted = vim.deepcopy(values)
  table.sort(sorted)
  local index = math.max(1, math.min(#sorted, math.ceil(#sorted * fraction)))
  return sorted[index]
end

function M.measure(options, callback)
  local warmup = options.warmup or 5
  local iterations = options.iterations or 30
  local durations = {}
  local memory = {}
  local checksum = 0

  for _ = 1, warmup do
    local result = callback()
    checksum = checksum + (type(result) == "table" and #result or type(result) == "string" and #result or type(result) == "number" and result or 0)
  end

  for _ = 1, iterations do
    collectgarbage("collect")
    local before = collectgarbage("count")
    local started = uv.hrtime()
    local result = callback()
    local elapsed = (uv.hrtime() - started) / 1000000
    local after = collectgarbage("count")
    checksum = checksum + (type(result) == "table" and #result or type(result) == "string" and #result or type(result) == "number" and result or 0)
    table.insert(durations, elapsed)
    table.insert(memory, math.max(0, after - before))
  end

  return {
    name = options.name,
    iterations = iterations,
    p50_ms = percentile(durations, 0.50),
    p95_ms = percentile(durations, 0.95),
    max_ms = math.max(unpack(durations)),
    max_memory_kb = math.max(unpack(memory)),
    checksum = checksum,
  }
end

function M.check(stats, sla)
  stats.timing_pass = stats.p95_ms <= sla.p95_ms
  stats.memory_pass = stats.max_memory_kb <= sla.max_memory_kb
  stats.pass = stats.timing_pass and stats.memory_pass
  stats.sla = sla
  return stats.pass
end

function M.print(stats)
  print(vim.json.encode(stats))
end

return M
