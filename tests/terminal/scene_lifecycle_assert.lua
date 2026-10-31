local mode = vim.env.PROUD_SCENE_LIFECYCLE_MODE
local current = require("proud.session").current
local state = current and current.state
local scene = state and (state.surface or state.workspace)
local ok = false

if scene then
  vim.wait(1000, scene.lifecycle.closed, 10)
  if mode == "replacement" then
    ok = current.feature == "pull_request_overview"
      and not scene.lifecycle.closed()
      and vim.api.nvim_tabpage_is_valid(scene.tabpage)
  else
    ok = scene.lifecycle.closed()
      and not vim.api.nvim_tabpage_is_valid(scene.tabpage)
  end
end

local marker = ({
  ["buffer-delete"] = "BUFFER_DELETE_OK",
  replacement = "REPLACEMENT_OK",
})[mode] or "SCENE_LIFECYCLE_OK"
vim.api.nvim_echo({ { ("%s=%s"):format(marker, tostring(ok)) } }, false, {})
