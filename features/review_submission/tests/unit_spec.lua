return function(test)
  local feature = require("proud.loader").load("review_submission")
  local state = feature.create({ number = 482 }, { event = "request changes" })

  test.eq("REQUEST_CHANGES", feature.selected(state).event, "review decision names are normalized")
  test.truthy(feature.select_delta(state, 1) ~= nil)
  test.eq("COMMENT", feature.selected(state).event, "decision navigation wraps")
  local valid, error_message = feature.validate(state)
  test.truthy(not valid)
  test.contains(error_message, "review body")

  feature.set_body(state, "Please cap the retry delay.")
  valid = feature.validate(state)
  test.truthy(valid, "a non-empty comment body is valid")

  feature.select_delta(state, 1)
  test.eq("APPROVE", feature.selected(state).event)
  test.truthy(feature.validate(state), "approvals may omit a review body")

  local view = feature.render(state, 42)
  test.contains(table.concat(view.lines, "\n"), "Review #482")
  test.contains(table.concat(view.lines, "\n"), "Approve")
  test.highlighted(view, "Approve", "ProudAccent", "selected review decision uses the solid purple button")
  test.highlighted(view, "Comment", "ProudMuted", "unselected review decisions stay grey")
  test.highlighted(view, "Submit review", "ProudAccentText", "submission action is accented")

  local body_view = feature.render_body(state)
  test.highlighted(body_view, "Please cap the retry delay.", "ProudBright", "review body text is bright")

  local submitted_event, submitted_body
  local callback_ok
  local success_result
  feature.submit(state, {
    on_submit = function(event, body, callback)
      submitted_event, submitted_body = event, body
      callback(true, { id = 922 })
    end,
    on_success = function(result)
      success_result = result
    end,
  }, function(ok)
    callback_ok = ok
  end)
  test.truthy(callback_ok)
  test.eq("APPROVE", submitted_event)
  test.eq("Please cap the retry delay.", submitted_body)
  test.eq("Review submitted", state.status)
  test.eq({ id = 922 }, success_result, "successful submission forwards its result to on_success")
  test.eq("ProudSuccessText", state.status_group)
  test.highlighted(feature.render(state, 42), "Review submitted", "ProudSuccessText", "successful status is semantic")

  state.status = ""
  feature.submit(state, {
    on_submit = function(_, _, callback)
      callback(false, { message = "GitHub rejected the review" })
    end,
  })
  test.eq("GitHub rejected the review", state.status, "submission failures remain visible for correction")
  test.eq("ProudDangerText", state.status_group)
  test.highlighted(
    feature.render(state, 42),
    "GitHub rejected the review",
    "ProudDangerText",
    "failed status is destructive"
  )

  state.status = ""
  feature.submit(state, {
    on_submit = function(_, _, callback)
      callback(false, { message = "Network unavailable" })
    end,
    on_success = function()
      error("on_success must not run after a failed submission")
    end,
  })

  local provider_request
  local provider = require("proud.provider").github({
    client = {
      submit_pull_request_review = function(_, number, event, body, callback)
        provider_request = { number = number, event = event, body = body }
        callback(true, { id = 955 })
      end,
    },
  })
  local provider_ok
  provider:submit_review(482, "REQUEST_CHANGES", "Please add a regression test.", function(ok)
    provider_ok = ok
  end)
  test.truthy(provider_ok)
  test.eq({
    number = 482,
    event = "REQUEST_CHANGES",
    body = "Please add a regression test.",
  }, provider_request, "provider delegates review submission to the GitHub client")
end
