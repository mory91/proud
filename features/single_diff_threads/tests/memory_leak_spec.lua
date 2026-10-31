return function(test)
  local result = require("memory_leak")("single", { warmup_cycles = 20, measured_cycles = 20 })
  test.truthy(result.ok, "full-file diff has no E2E memory leak")
  test.truthy(result.growth_kb <= result.max_growth_kb, "full-file diff heap growth stays within SLA")
  test.truthy(result.resources_stable, "full-file diff releases windows and buffers")
end
