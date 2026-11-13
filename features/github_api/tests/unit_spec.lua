return function(test)
  local github = require("proud.loader").load("github_api")
  local requests = {}
  local replies = {}
  local client = github.new({
    repository = "acme/widget",
    token = "test-token",
    page_size = 2,
    transport = function(request, callback)
      table.insert(requests, request)
      callback(table.remove(replies, 1))
    end,
  })

  test.eq("github_api", github.name)
  test.eq("18s", github.check_duration({ duration = 18 }))
  test.eq("6m 40s", github.check_duration({
    started_at = "2026-10-18T12:00:00Z",
    completed_at = "2026-10-18T12:06:40Z",
  }))
  test.eq("1h 02m", github.check_duration({
    started_at = "2026-10-18T12:00:00Z",
    completed_at = "2026-10-18T13:02:05Z",
  }))
  test.eq("", github.check_duration({ started_at = "2026-10-18T12:00:00Z" }))

  table.insert(replies, { code = 200, stdout = '{"id": 17}' })
  local done, request_ok, repository = false
  client:request({ method = "GET", path = "/repos/acme/widget", query = { page = 2 } }, function(ok, value)
    done, request_ok, repository = true, ok, value
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.truthy(request_ok)
  test.eq(17, repository.id)
  test.eq("GET", requests[1].method)
  test.eq("https://api.github.com/repos/acme/widget?page=2", requests[1].url)
  test.eq("Bearer test-token", requests[1].headers.Authorization)
  test.eq("application/vnd.github+json", requests[1].headers.Accept)
  test.eq("2022-11-28", requests[1].headers["X-GitHub-Api-Version"])

  local command = github.transport_command()
  test.eq("curl", command[1])
  test.contains(command, "--config")
  test.truthy(not table.concat(command, " "):find("test-token", 1, true))
  local curl_config = github.curl_config(requests[1])
  test.contains(curl_config, 'header = "Authorization: Bearer test-token"')
  test.contains(curl_config, 'write-out = "\\n%{http_code}"')

  table.insert(replies, {
    code = 406,
    stdout = '{"message":"Sorry, the diff exceeded the maximum number of lines (20000)"}',
  })
  done = false
  local error_ok, api_error
  client:request({ method = "GET", path = "/repos/acme/widget/pulls/482.diff", accept = "application/vnd.github.v3.diff" }, function(ok, value)
    done, error_ok, api_error = true, ok, value
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.truthy(not error_ok)
  test.eq(406, api_error.code)
  test.truthy(api_error.too_large)
  test.contains(api_error.message, "maximum number of lines")

  for page = 1, 2 do
    table.insert(replies, {
      code = 200,
      stdout = page == 1
          and '[{"filename":"one.ts","patch":"@@ -1 +1 @@\\n-a\\n+b"},{"filename":"two.ts","patch":"@@ -1 +1 @@\\n-c\\n+d"}]'
        or '[{"filename":"three.ts","patch":"@@ -1 +1 @@\\n-e\\n+f"}]',
    })
  end
  done = false
  local files_ok, files
  client:list_pull_request_files(482, function(ok, value)
    done, files_ok, files = true, ok, value
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.truthy(files_ok)
  test.eq(3, #files)
  test.eq("three.ts", files[3].filename)
  test.eq(1, requests[3].query.page)
  test.eq(2, requests[4].query.page)
  test.contains(requests[3].path, "/repos/acme/widget/pulls/482/files")

  table.insert(replies, {
    code = 200,
    stdout = [[{"data":{"search":{
      "issueCount":14,
      "pageInfo":{"hasNextPage":true,"endCursor":"next-page"},
      "nodes":[
        {"number":482,"title":"Retry","reviewThreads":{"totalCount":3}},
        {"number":481,"title":"Polish","reviewThreads":{"totalCount":1}},
        {"number":480,"title":"Cleanup","reviewThreads":{"totalCount":0}}
      ]
    }}}]],
  })
  done = false
  local pulls_ok, pulls
  client:list_pull_requests_page("author:sara-k retry", 2, "previous-page", function(ok, value)
    done, pulls_ok, pulls = true, ok, value
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.truthy(pulls_ok)
  test.eq(482, pulls.items[1].number)
  test.eq({ 3, 1, 0 }, {
    pulls.items[1].reviewThreads.totalCount,
    pulls.items[2].reviewThreads.totalCount,
    pulls.items[3].reviewThreads.totalCount,
  }, "GraphQL search preserves raw review-thread totals")
  test.eq(14, pulls.total_count, "GraphQL search exposes the filtered total")
  test.truthy(pulls.has_next_page)
  test.eq("next-page", pulls.next_cursor)
  test.eq("POST", requests[5].method)
  test.eq("/graphql", requests[5].path)
  local pull_query = vim.json.decode(requests[5].body)
  test.eq("type:pr repo:acme/widget author:sara-k retry", pull_query.variables.query)
  test.eq(2, pull_query.variables.first)
  test.eq("previous-page", pull_query.variables.after)
  test.truthy(not pull_query.query:find("body", 1, true), "pull request pages omit description bodies")
  test.contains(pull_query.query, "issueCount")
  test.contains(pull_query.query, "pageInfo")
  test.contains(pull_query.query, "reviewThreads { totalCount }")
  test.contains(pull_query.query, "additions")
  test.contains(pull_query.query, "deletions")
  test.contains(pull_query.query, "labels(first: 100) { nodes { name } }")
  test.contains(pull_query.query, "reviewRequests(first: 20)")
  test.contains(pull_query.query, "latestReviews(first: 20)")

  table.insert(replies, { code = 201, stdout = '{"id":901}' })
  done = false
  local comment_ok, comment
  client:post_issue_comment(482, "looks good", function(ok, value)
    done, comment_ok, comment = true, ok, value
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.truthy(comment_ok)
  test.eq(901, comment.id)
  test.eq("POST", requests[6].method)
  test.contains(requests[6].path, "/repos/acme/widget/issues/482/comments")
  test.eq({ body = "looks good" }, vim.json.decode(requests[6].body))

  table.insert(replies, { code = 200, stdout = "diff --git a/a.ts b/a.ts\n" })
  done = false
  local diff_ok, patch
  client:get_pull_request_diff(482, function(ok, value)
    done, diff_ok, patch = true, ok, value
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.truthy(diff_ok)
  test.contains(patch, "diff --git")
  test.eq("application/vnd.github.v3.diff", requests[7].headers.Accept)
  test.eq("/repos/acme/widget/pulls/482", requests[7].path)

  table.insert(replies, {
    code = 406,
    stdout = '{"message":"Sorry, the diff exceeded the maximum number of lines (20000)","documentation_url":"https://docs.github.com"}',
  })
  done = false
  local raw_error_ok, raw_error
  client:get_pull_request_diff(999, function(ok, value)
    done, raw_error_ok, raw_error = true, ok, value
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.truthy(not raw_error_ok)
  test.eq("Sorry, the diff exceeded the maximum number of lines (20000)", raw_error.message)
  test.truthy(raw_error.too_large)

  local previous_env_token = vim.env.PROUD_GITHUB_TOKEN
  vim.env.PROUD_GITHUB_TOKEN = "environment-token"
  done = false
  local resolved_token
  github.resolve_token({}, function(token)
    done, resolved_token = true, token
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.eq("environment-token", resolved_token)
  vim.env.PROUD_GITHUB_TOKEN = previous_env_token

  local rebuilt = github.build_patch_from_files({
    {
      filename = "src/retry.ts",
      status = "MODIFIED",
      patch = "@@ -1,1 +1,1 @@\n-old\n+new\n",
    },
    {
      filename = "src/config.ts",
      status = "ADDED",
      patch = "@@ -0,0 +1,2 @@\n+one\n+two\n",
    },
    {
      filename = "src/new-name.ts",
      previous_filename = "src/old-name.ts",
      status = "RENAMED",
      patch = "@@ -1,1 +1,1 @@\n-old\n+new\n",
    },
    {
      filename = "assets/logo.bin",
      status = "MODIFIED",
    },
  })
  local rebuilt_files = require("proud.diff").parse_patch(rebuilt)
  test.eq(4, #rebuilt_files)
  test.eq("src/old-name.ts", rebuilt_files[3].old_path)
  test.eq("assets/logo.bin", rebuilt_files[4].path)

  test.eq("acme/widget", github.parse_repository("git@github.com:acme/widget.git"))
  test.eq("acme/widget", github.parse_repository("https://github.com/acme/widget.git"))
  test.eq("acme/widget", github.parse_repository("ssh://git@github.com/acme/widget"))

  table.insert(replies, { code = 200, stdout = '{"errors":[{"message":"bad search query"}]}' })
  done = false
  local graphql_error_ok, graphql_error
  client:list_pull_requests("is:open", 50, function(ok, value)
    done, graphql_error_ok, graphql_error = true, ok, value
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.truthy(not graphql_error_ok)
  test.eq("bad search query", graphql_error.message)

  table.insert(replies, { code = 200, stdout = '{"data":{}}' })
  done = false
  local malformed_ok, malformed
  client:list_pull_requests("is:open", 50, function(ok, value)
    done, malformed_ok, malformed = true, ok, value
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.truthy(not malformed_ok)
  test.eq("GitHub GraphQL returned an unexpected search payload", malformed.message)

  table.insert(replies, {
    code = 200,
    stdout = [[{"data":{"repository":{"pullRequest":{"body":"First message loaded on demand."}}}}]],
  })
  done = false
  local description_ok, description
  client:get_pull_request_description(482, function(ok, value)
    done, description_ok, description = true, ok, value
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.truthy(description_ok)
  test.eq("First message loaded on demand.", description)
  local description_request = vim.json.decode(requests[#requests].body)
  test.eq("/graphql", requests[#requests].path)
  test.eq({ owner = "acme", name = "widget", number = 482 }, description_request.variables)
  test.contains(description_request.query, "pullRequest(number: $number)")
  test.contains(description_request.query, "body")
  table.insert(replies, { code = 200, stdout = '{"id":911,"state":"APPROVED"}' })
  done = false
  local review_ok, review
  client:submit_pull_request_review(482, "approve", "", function(ok, value)
    done, review_ok, review = true, ok, value
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.truthy(review_ok)
  test.eq(911, review.id)
  local review_request = requests[#requests]
  test.eq("POST", review_request.method)
  test.contains(review_request.path, "/repos/acme/widget/pulls/482/reviews")
  test.eq({ event = "APPROVE", body = "" }, vim.json.decode(review_request.body))

  local request_count = #requests
  done = false
  local invalid_ok, invalid_error
  client:submit_pull_request_review(482, "dismiss", "reason", function(ok, value)
    done, invalid_ok, invalid_error = true, ok, value
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.truthy(not invalid_ok)
  test.contains(invalid_error.message, "comment, approve, or request changes")
  test.eq(request_count, #requests, "invalid review events never reach the transport")

  done = false
  client:submit_pull_request_review(482, "request-changes", "  ", function(ok, value)
    done, invalid_ok, invalid_error = true, ok, value
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.truthy(not invalid_ok)
  test.contains(invalid_error.message, "review body is required")
  test.eq(request_count, #requests, "empty request-changes bodies never reach the transport")

  client.page_size = 1
  table.insert(replies, {
    code = 200,
    stdout = '{"total_count":2,"check_runs":[{"id":1,"name":"lint","conclusion":"success"}]}',
  })
  table.insert(replies, {
    code = 200,
    stdout = '{"total_count":2,"check_runs":[{"id":2,"name":"e2e","conclusion":"failure"}]}',
  })
  local check_request_count = #requests
  done = false
  local checks_ok, checks
  client:list_check_runs("head-sha", function(ok, value)
    done, checks_ok, checks = true, ok, value
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.truthy(checks_ok)
  test.eq(2, #checks, "wrapped GitHub check-run pages are flattened")
  test.eq("lint", checks[1].name)
  test.eq("e2e", checks[2].name)
  test.eq(check_request_count + 2, #requests, "total_count stops wrapped pagination at the final page")
  test.eq(1, requests[check_request_count + 1].query.page)
  test.eq(2, requests[check_request_count + 2].query.page)

  table.insert(replies, {
    code = 200,
    stdout = [[{
      "data":{"repository":{"pullRequest":{"statusCheckRollup":{"contexts":{
        "nodes":[{"__typename":"CheckRun","databaseId":1,"name":"lint","status":"COMPLETED","conclusion":"SUCCESS"}],
        "pageInfo":{"hasNextPage":true,"endCursor":"check-page-2"}
      }}}}}
    }]],
  })
  table.insert(replies, {
    code = 200,
    stdout = [[{
      "data":{"repository":{"pullRequest":{"statusCheckRollup":{"contexts":{
        "nodes":[{"__typename":"StatusContext","id":"status-2","context":"preview","state":"PENDING"}],
        "pageInfo":{"hasNextPage":false,"endCursor":null}
      }}}}}
    }]],
  })
  local checks_request_count = #requests
  done = false
  local graphql_checks_ok, graphql_checks
  client:get_pull_request_checks(482, function(ok, value)
    done, graphql_checks_ok, graphql_checks = true, ok, value
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.truthy(graphql_checks_ok)
  test.eq(2, #graphql_checks, "PR-level GraphQL contexts are cursor-paginated")
  test.eq("lint", graphql_checks[1].name)
  test.eq("preview", graphql_checks[2].context)
  test.eq(checks_request_count + 2, #requests)
  test.eq("/graphql", requests[checks_request_count + 1].path)
  local first_check_body = vim.json.decode(requests[checks_request_count + 1].body)
  local second_check_body = vim.json.decode(requests[checks_request_count + 2].body)
  test.contains(first_check_body.query, "pullRequest(number: $number)")
  test.contains(first_check_body.query, "statusCheckRollup")
  test.eq("check-page-2", second_check_body.variables.after)

  table.insert(replies, { code = 200, stdout = '{"data":{"repository":{"pullRequest":{"statusCheckRollup":null}}}}' })
  done = false
  client:get_pull_request_checks(482, function(ok, value)
    done = true
    test.truthy(ok, "a PR without checks is a successful empty result")
    test.eq({}, value)
  end)
  test.truthy(vim.wait(1000, function() return done end, 10))
  table.insert(replies, { code = 200, stdout = '{"total_count":1,"check_runs":[{"id":1,"name":"lint","conclusion":"failure"}]}' })
  done = false
  client:list_check_runs("head-sha", function(ok, value)
    done = true
    test.truthy(ok)
    test.eq("failure", value[1].conclusion, "check polling bypasses the previous REST response cache")
  end)
  test.truthy(vim.wait(1000, function() return done end, 10))

  -- Review threads, replies, resolving and pending reviews.
  local function call(method, ...)
    local args = { ... }
    local finished, result_ok, result = false
    args[#args + 1] = function(ok, value)
      finished, result_ok, result = true, ok, value
    end
    client[method](client, unpack(args))
    vim.wait(1000, function() return finished end, 10)
    return result_ok, result, requests[#requests]
  end
  local function graphql_body(request)
    return vim.json.decode(request.body)
  end

  table.insert(replies, { code = 200, stdout = vim.json.encode({ data = { repository = { pullRequest = {
    id = "PR_1",
    author = { login = "sara-k" },
    reviews = { nodes = { { id = "PRR_9", databaseId = 9 } } },
    reviewThreads = { nodes = { {
      id = "PRRT_1", isResolved = false, isOutdated = false, path = "src/retry.ts", line = 14,
      comments = { nodes = { { id = "PRRC_1", databaseId = 101, body = "Intended?", createdAt = "2026-10-18T12:00:00Z", state = "SUBMITTED", author = { login = "dev-lee" } } } },
    } } },
  } } } }) })
  local threads_ok, pull, threads_request = call("list_review_threads", 482)
  test.truthy(threads_ok, "review threads load")
  test.eq("/graphql", threads_request.path)
  test.eq("POST", threads_request.method)
  test.contains(graphql_body(threads_request).query, "reviewThreads", "threads come from GraphQL")
  test.eq({ owner = "acme", name = "widget", number = 482 }, graphql_body(threads_request).variables)
  test.eq("PRRT_1", pull.reviewThreads.nodes[1].id, "thread ids are returned")

  table.insert(replies, { code = 201, stdout = '{"id": 202, "body": "Agreed", "user": {"login": "morteza"}}' })
  local reply_ok, reply, reply_request = call("reply_to_review_comment", 482, 101, "Agreed")
  test.truthy(reply_ok, "replies post")
  test.eq(202, reply.id)
  test.eq("POST", reply_request.method)
  test.contains(reply_request.path, "/repos/acme/widget/pulls/482/comments/101/replies", "replies go under the thread's top comment")
  test.eq({ body = "Agreed" }, vim.json.decode(reply_request.body))

  table.insert(replies, { code = 200, stdout = '{"data": {"resolveReviewThread": {"thread": {"id": "PRRT_1", "isResolved": true}}}}' })
  local resolve_ok, resolved, resolve_request = call("resolve_review_thread", "PRRT_1")
  test.truthy(resolve_ok and resolved.isResolved, "threads resolve")
  test.contains(graphql_body(resolve_request).query, "resolveReviewThread")
  test.eq({ thread = "PRRT_1" }, graphql_body(resolve_request).variables)

  table.insert(replies, { code = 200, stdout = '{"data": {"addPullRequestReview": {"pullRequestReview": {"id": "PRR_10", "databaseId": 10}}}}' })
  local review_ok, pending, pending_request = call("create_pending_review", "PR_1")
  test.truthy(review_ok, "a pending review starts")
  test.eq("PRR_10", pending.id)
  test.eq({ pull = "PR_1" }, graphql_body(pending_request).variables)
  test.truthy(not graphql_body(pending_request).query:find("event", 1, true), "a review without an event stays pending")

  table.insert(replies, { code = 200, stdout = '{"data": {"addPullRequestReviewThreadReply": {"comment": {"id": "PRRC_2", "databaseId": 103, "body": "Later", "state": "PENDING"}}}}' })
  local pending_ok, pending_comment, pending_reply = call("add_review_thread_reply", "PRRT_1", "Later", "PRR_10")
  test.truthy(pending_ok and pending_comment.state == "PENDING", "replies can join the pending review")
  test.eq({ thread = "PRRT_1", body = "Later", review = "PRR_10" }, graphql_body(pending_reply).variables)

  table.insert(replies, { code = 200, stdout = '{"data": {"submitPullRequestReview": {"pullRequestReview": {"id": "PRR_10", "state": "COMMENTED"}}}}' })
  local submit_ok, submitted, submit_request = call("submit_pending_review", "PRR_10", "comment", "Looks good")
  test.truthy(submit_ok and submitted.state == "COMMENTED", "the pending review is submitted")
  test.eq({ review = "PRR_10", event = "COMMENT", body = "Looks good" }, graphql_body(submit_request).variables)

  local before = #requests
  local invalid_submit_ok, invalid_submit = call("submit_pending_review", "PRR_10", "dismiss", "")
  test.truthy(not invalid_submit_ok, "invalid events are rejected")
  test.contains(invalid_submit.message, "comment, approve, or request changes")
  test.eq(before, #requests, "invalid events never reach GitHub")

  table.insert(replies, { code = 200, stdout = '{"errors": [{"message": "Resource not accessible by integration"}]}' })
  local denied_ok, denied = call("resolve_review_thread", "PRRT_1")
  test.truthy(not denied_ok, "GraphQL errors fail the call")
  test.eq("Resource not accessible by integration", denied.message, "GitHub's message is kept")
end
