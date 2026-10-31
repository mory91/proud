local mode = vim.env.PROUD_REVIEW_MODE or "initial"
local session = require("proud.session")
local state = session.current and session.current.state
local feature = require("proud.loader").load("review_submission")
local ok = session.current and session.current.feature == "review_submission" and state ~= nil

if ok then
  local workspace = state.workspace
  ok = ok and workspace ~= nil
    and workspace.order[1] == "decisions"
    and workspace.order[2] == "body"
    and vim.api.nvim_buf_is_valid(workspace.panes.body.buffer)
    and vim.bo[workspace.panes.body.buffer].modifiable
  if mode == "initial" then
    ok = ok and feature.selected(state).event == "COMMENT"
    ok = ok and state.status == ""
  elseif mode == "approved" then
    ok = ok and feature.selected(state).event == "APPROVE"
  elseif mode == "submitted" then
    ok = ok and state.status == "Review submitted"
    ok = ok and table.concat(state.body_lines, "\n"):find("Looks good", 1, true) ~= nil
  elseif mode == "opened" then
    ok = ok and state.pull.number == 482
  end
end

if ok then
  vim.api.nvim_echo({ { ("REVIEW_%s_OK=true"):format(mode:upper()) } }, false, {})
else
  vim.api.nvim_echo({ { ("REVIEW_%s_OK=false"):format(mode:upper()) } }, false, {})
end
