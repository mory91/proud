local feature = require("proud.loader").load("github_credentials")
local opened = false
feature.ensure({
  token_path = feature.default_token_path(),
  credential = false,
  validate = function(_, callback)
    callback(true, {})
  end,
  open_prompt = function()
    opened = true
  end,
}, function(ok, token)
  local passed = ok and token == "github_pat_terminal" and not opened
  vim.api.nvim_echo({
    { passed and "CREDENTIALS_REUSE_OK" or "CREDENTIALS_REUSE_FAIL" },
  }, false, {})
end)
