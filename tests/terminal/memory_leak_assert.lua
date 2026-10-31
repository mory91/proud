local result = dofile(vim.env.PROUD_ROOT .. "/tests/memory_leak.lua")(vim.env.PROUD_MEMORY_SCREEN, {
  warmup_cycles = 20,
  measured_cycles = 20,
  max_growth_kb = 64,
})
local message = table.concat({
  "MEMORY_LEAK_OK=" .. tostring(result.ok),
  "screen=" .. result.screen,
  "growth_kb=" .. string.format("%.2f", result.growth_kb),
  "trend_kb=" .. string.format("%.2f", result.trend_kb),
  "buffers=" .. result.final_buffers,
  "windows=" .. result.final_windows,
  "resources=" .. tostring(result.resources_stable),
}, " ")
vim.api.nvim_echo({ { message } }, false, {})
