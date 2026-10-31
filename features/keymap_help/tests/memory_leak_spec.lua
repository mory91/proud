return function(test)
  local result = require("memory_leak")("help")
  test.truthy(result.ok, "help screen has no E2E memory leak")
  test.truthy(result.growth_kb <= result.max_growth_kb, "help heap growth stays within SLA")
  test.truthy(result.resources_stable, "help releases windows and buffers")
end
