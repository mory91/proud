local feature = require("proud.loader").load("github_credentials")

local states = {}
local prompt_values = {}
for index = 1, 100 do
  table.insert(states, feature.create({
    token_path = "/tmp/proud/credentials/" .. index,
    error = ("HTTP 401: Credential validation failed with request %03d"):format(index),
  }))
  table.insert(prompt_values, ("github_pat_benchmark_%03d"):format(index))
end
local prompt_buffers = {}
for index = 1, 100 do
  local prompt_buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[prompt_buffer].buftype = "nofile"
  vim.bo[prompt_buffer].swapfile = false
  vim.bo[prompt_buffer].undofile = false
  vim.bo[prompt_buffer].undolevels = -1
  vim.bo[prompt_buffer].modifiable = true
  vim.api.nvim_buf_set_lines(prompt_buffer, 0, -1, false, { prompt_values[index] })
  table.insert(prompt_buffers, prompt_buffer)
end

return {
  workloads = {
    {
      options = {
        name = "github_credentials.render_100_validation_errors",
        iterations = 40,
        warmup = 8,
      },
      sla = {
        p95_ms = 2,
        max_memory_kb = 256,
      },
      run = function()
        local lines = 0
        for _, state in ipairs(states) do
          lines = lines + #feature.render(state).lines
        end
        return lines
      end,
    },
    {
      options = {
        name = "github_credentials.mask_100_prompt_buffers",
        iterations = 40,
        warmup = 8,
      },
      sla = {
        p95_ms = 2,
        max_memory_kb = 128,
      },
      run = function()
        for _, prompt_buffer in ipairs(prompt_buffers) do
          feature.mask_prompt(prompt_buffer)
        end
        return #prompt_buffers
      end,
    },
  },
}
