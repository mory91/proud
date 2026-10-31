local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
local github = require("proud.loader").load("github_api")
local repository = vim.env.PROUD_GITHUB_REPOSITORY or "neovim/neovim"
local client = github.new({
  repository = repository,
  base_url = vim.env.PROUD_GITHUB_API_URL,
  token = vim.env.PROUD_GITHUB_TOKEN or vim.env.GITHUB_TOKEN,
  token_file = vim.env.PROUD_GITHUB_TOKEN_FILE,
  cwd = vim.env.PROUD_GITHUB_REPO_PATH or root,
})

local done, ok, value = false
client:get_repository(function(call_ok, result)
  done, ok, value = true, call_ok, result
end)

local completed = vim.wait(15000, function()
  return done
end, 25)
if not completed then
  io.stderr:write("GitHub API live smoke test timed out\n")
  os.exit(1)
end
if not ok then
  io.stderr:write("GitHub API live smoke test failed: " .. vim.inspect(value) .. "\n")
  os.exit(1)
end
print(("PASS GitHub API live smoke test: %s (#%s)"):format(value.full_name or repository, tostring(value.id or "?")))
