return function(test)
  local result = require("memory_leak")("compare")
  test.truthy(result.ok, "branch compare has no E2E memory leak")
  test.truthy(result.growth_kb <= result.max_growth_kb, "compare heap growth stays within SLA")
  test.truthy(result.resources_stable, "compare releases windows and buffers")
end
