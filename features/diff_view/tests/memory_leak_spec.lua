return function(test)
  local result = require("memory_leak")("diff", { warmup_cycles = 20, measured_cycles = 20 })
  test.truthy(result.ok, "pull request diff has no E2E memory leak")
  test.truthy(result.growth_kb <= result.max_growth_kb, "pull request diff heap growth stays within SLA")
  test.truthy(result.resources_stable, "pull request diff releases windows and buffers")
end
