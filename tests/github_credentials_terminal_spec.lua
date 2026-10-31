local feature = require("proud.loader").load("github_credentials")
local token_path = feature.default_token_path()
vim.fn.delete(token_path)

local state
state = feature.create({
  token_path = token_path,
  credential = false,
  validate = function(token, callback)
    vim.schedule(function()
      callback(token == "github_pat_terminal", token == "github_pat_terminal" and {} or {
        message = "HTTP 401: Token rejected",
      })
    end)
  end,
  on_success = function(token)
    local centered = state.modal_config ~= nil
      and state.modal_config.relative == "editor"
      and state.modal_config.row == math.floor((vim.o.lines - state.modal_config.height) / 2)
      and state.modal_config.col == math.floor((vim.o.columns - state.modal_config.width) / 2)
    vim.api.nvim_echo({
      { centered and token == "github_pat_terminal" and "CREDENTIALS_TERMINAL_OK" or "CREDENTIALS_TERMINAL_FAIL" },
    }, false, {})
  end,
})

local buffer, window = feature.open(state)
local config = vim.api.nvim_win_get_config(window)
state.modal_config = config
local centered = config.relative == "editor"
  and config.row == math.floor((vim.o.lines - config.height) / 2)
  and config.col == math.floor((vim.o.columns - config.width) / 2)
local visible = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n"):find("GitHub token required", 1, true) ~= nil
vim.api.nvim_echo({
  { centered and visible and "CREDENTIALS_MODAL_CENTERED" or "CREDENTIALS_MODAL_FAIL" },
}, false, {})
