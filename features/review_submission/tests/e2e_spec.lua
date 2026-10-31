return function(test)
  local feature = require("proud.loader").load("review_submission")
  local submitted
  local state = feature.create({ number = 482 }, { event = "COMMENT" })
  local body_buffer, workspace = feature.open(state, {
    name = "proud://review-e2e",
    on_submit = function(event, body, callback)
      submitted = { event = event, body = body }
      callback(true, { id = 933 })
    end,
  })

  test.eq({ "decisions", "body" }, workspace.order, "review composer uses two native panes")
  test.eq(body_buffer, workspace.panes.body.buffer)
  vim.api.nvim_buf_set_lines(body_buffer, 0, -1, false, { "Looks good with one small follow-up." })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "x", false)
  test.eq("APPROVE", feature.selected(state).event, "tab selects the next review decision")
  vim.api.nvim_feedkeys("S", "x", false)
  test.eq("APPROVE", submitted.event, "submit action sends the selected review event")
  test.eq("Looks good with one small follow-up.", submitted.body, "submit action reads the editable body pane")
  test.eq("Review submitted", state.status)

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<S-Tab>", true, false, true), "x", false)
  test.eq("COMMENT", feature.selected(state).event, "shift-tab selects the previous review decision")
  vim.cmd("silent! tabclose!")
end
