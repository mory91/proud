return function(test)
  local result = require("memory_leak")("browser", { warmup_cycles = 20, measured_cycles = 20 })
  test.truthy(result.ok, "PR browser has no E2E memory leak")
  test.truthy(result.growth_kb <= result.max_growth_kb, "PR browser heap growth stays within SLA")
  test.truthy(result.resources_stable, "PR browser releases windows and buffers")
end
