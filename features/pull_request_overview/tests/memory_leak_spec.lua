return function(test)
  local result = require("memory_leak")("overview")
  test.truthy(result.ok, "pull request overview has no E2E memory leak")
  test.truthy(result.growth_kb <= result.max_growth_kb, "overview heap growth stays within SLA")
  test.truthy(result.resources_stable, "overview releases windows and buffers")
end
