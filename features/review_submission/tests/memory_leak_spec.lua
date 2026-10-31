return function(test)
  local result = require("memory_leak")("review")
  test.truthy(result.ok, "review composer has no E2E memory leak")
  test.truthy(result.growth_kb <= result.max_growth_kb, "review composer heap growth stays within SLA")
  test.truthy(result.resources_stable, "review composer releases windows and buffers")
end
