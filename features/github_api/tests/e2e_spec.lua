return function(test)
  local github = require("proud.loader").load("github_api")
  local requests = {}
  local replies = {
    ["/repos/acme/widget/pulls/482"] = {
      number = 482,
      title = "Use resilient retries",
      user = { login = "sara-k" },
      head = { ref = "feat/retry", sha = "head-sha" },
      merge_commit_sha = "merge-sha",
      base = { ref = "main" },
      state = "open",
    },
    ["/repos/acme/widget/pulls/482/files"] = {
      { filename = "retry.ts", status = "MODIFIED", additions = 4, deletions = 2, patch = "@@ -1 +1 @@\n-a\n+b" },
    },
    ["/repos/acme/widget/pulls/482/commits"] = {
      { sha = "commit-sha", commit = { message = "Retry failed jobs" } },
    },
    ["/repos/acme/widget/commits/head-sha/check-runs"] = {
      total_count = 0,
      check_runs = {},
    },
    ["/repos/acme/widget/commits/head-sha/status"] = { statuses = {} },
    ["/repos/acme/widget/commits/merge-sha/check-runs"] = { total_count = 0, check_runs = {} },
    ["/repos/acme/widget/commits/merge-sha/status"] = {
      statuses = {},
    },
    ["/repos/acme/widget/pulls/482/reviews"] = {
      { id = 601, user = { login = "changes-reviewer" }, state = "CHANGES_REQUESTED", body = "" },
    },
    ["/repos/acme/widget/pulls/482/comments"] = {
      {
        id = 701,
        pull_request_review_id = 601,
        user = { login = "inline-reviewer" },
        body = "This retry condition is inverted.",
      },
      {
        id = 702,
        in_reply_to_id = 701,
        user = { login = "inline-author" },
        body = "Fixed in the next push.",
      },
    },
    ["/repos/acme/widget/issues/482/comments"] = {
      { user = { login = "comment-author" }, body = "The API conversation comment." },
    },
  }
  local client = github.new({
    repository = "acme/widget",
    token = "e2e-token",
    transport = function(request, callback)
      table.insert(requests, request)
      vim.schedule(function()
        local response = replies[request.path] or {}
        if request.path == "/graphql" then
          response = {
            data = {
              repository = {
                pullRequest = {
                  statusCheckRollup = {
                    contexts = {
                      nodes = {
                        {
                          __typename = "CheckRun",
                          databaseId = 901,
                          name = "unit",
                          status = "COMPLETED",
                          conclusion = "SUCCESS",
                          startedAt = "2026-10-18T12:00:00Z",
                          completedAt = "2026-10-18T12:00:18Z",
                        },
                        {
                          __typename = "CheckRun",
                          databaseId = 902,
                          name = "e2e / robot-studio",
                          status = "COMPLETED",
                          conclusion = "FAILURE",
                          startedAt = "2026-10-18T12:00:00Z",
                          completedAt = "2026-10-18T12:06:40Z",
                        },
                        {
                          __typename = "StatusContext",
                          id = "status-preview",
                          context = "preview",
                          state = "PENDING",
                        },
                      },
                      pageInfo = { hasNextPage = false, endCursor = vim.NIL },
                    },
                  },
                },
              },
            },
          }
        end
        callback({ code = 200, stdout = vim.json.encode(response) })
      end)
    end,
  })

  local done, ok, pull = false
  client:get_pull_request(482, function(call_ok, value)
    done, ok, pull = true, call_ok, value
  end)
  test.truthy(vim.wait(2000, function()
    return done
  end, 10), "GitHub SDK enriches pull request context asynchronously")
  test.truthy(ok)
  test.eq("Use resilient retries", pull.title)
  test.eq("retry.ts", pull.files[1].filename)
  test.eq("commit-sha", pull.commits[1].sha)
  test.eq(3, #pull.statusCheckRollup)
  test.contains(pull.statusCheckRollup[1].name, "unit")
  test.eq("18s", pull.statusCheckRollup[1].duration)
  test.eq("e2e / robot-studio", pull.statusCheckRollup[2].name)
  test.eq("6m 40s", pull.statusCheckRollup[2].duration)
  test.eq("preview", pull.statusCheckRollup[3].name)
  test.eq("PENDING", pull.statusCheckRollup[3].state)
  test.eq("changes-reviewer", pull.reviews[1].user.login)
  test.eq("comment-author", pull.comments[1].user.login)
  test.eq("This retry condition is inverted.", pull.review_comments[1].body)
  test.eq(11, #requests, "pull metadata, GraphQL checks, files, commits, checks, reviews, issue comments, and review comments are loaded through the SDK")
  local requested_paths = {}
  for _, request in ipairs(requests) do
    requested_paths[request.url] = true
  end
  local graphql_checks_requested = false
  local head_checks_requested = false
  local merge_checks_requested = false
  for url in pairs(requested_paths) do
    graphql_checks_requested = graphql_checks_requested or url == "https://api.github.com/graphql"
    head_checks_requested = head_checks_requested or url:find("/commits/head-sha/check-runs", 1, true) ~= nil
    merge_checks_requested = merge_checks_requested or url:find("/commits/merge-sha/check-runs", 1, true) ~= nil
  end
  test.truthy(graphql_checks_requested, "PR-level GraphQL check rollup is queried")
  test.truthy(head_checks_requested, "head check runs are queried")
  test.truthy(merge_checks_requested, "merge commit check runs are queried")
  for _, request in ipairs(requests) do
    test.truthy(
      request.url:find("https://api.github.com/repos/acme/widget/", 1, true) == 1
        or request.url == "https://api.github.com/graphql"
    )
  end
  local overview = require("proud.loader").load("pull_request_overview").create(pull)
  local overview_view = require("proud.loader").load("pull_request_overview").render(overview)
  local conversation_text = {}
  for _, card in ipairs(overview_view.conversation_cards or {}) do
    table.insert(conversation_text, table.concat(card.lines, "\n"))
  end
  test.contains(table.concat(conversation_text, "\n"), "This retry condition is inverted.", "inline review comments render as review replies")
  test.contains(table.concat(conversation_text, "\n"), "Fixed in the next push.", "review comment replies remain threaded")
  local check_node = require("proud.components.tree").find(overview.sidebar, "checks")
  test.truthy(check_node ~= nil, "GraphQL-only checks reach the overview sidebar")
  test.eq(3, #check_node.children, "check-run and status contexts are both listed")
  local check_header = table.concat(vim.tbl_map(function(section)
    return section.text or ""
  end, check_node.sections), " ")
  test.contains(check_header, "Checks 1 of 3 passing", "sidebar summarizes GraphQL checks")

  local graphql_request
  for _, request in ipairs(requests) do
    if request.path == "/graphql" then
      graphql_request = request
    end
  end
  local graphql_body = vim.json.decode(graphql_request.body)
  test.contains(graphql_body.query, "statusCheckRollup")
  test.contains(graphql_body.query, "... on CheckRun")
  test.contains(graphql_body.query, "... on StatusContext")

  local dedupe_client = github.new({
    repository = "acme/widget",
    token = "e2e-token",
    transport = function(request, callback)
      vim.schedule(function()
        local response
        if request.path == "/graphql" then
          response = {
            data = {
              repository = {
                pullRequest = {
                  statusCheckRollup = {
                    contexts = {
                      nodes = {
                        {
                          __typename = "CheckRun",
                          databaseId = 777,
                          name = "lint",
                          status = "COMPLETED",
                          conclusion = "SUCCESS",
                        },
                      },
                      pageInfo = { hasNextPage = false },
                    },
                  },
                },
              },
            },
          }
        elseif request.path == "/repos/acme/widget/commits/head-sha/check-runs" then
          response = {
            total_count = 1,
            check_runs = { { id = 777, name = "lint", conclusion = "success" } },
          }
        elseif request.path == "/repos/acme/widget/pulls/482" then
          response = vim.deepcopy(replies[request.path])
        elseif request.path == "/repos/acme/widget/commits/head-sha/status"
          or request.path == "/repos/acme/widget/commits/merge-sha/check-runs"
          or request.path == "/repos/acme/widget/commits/merge-sha/status"
        then
          response = request.path:find("/check-runs", 1, true)
              and { total_count = 0, check_runs = {} }
            or { statuses = {} }
        else
          response = replies[request.path] or {}
        end
        callback({ code = 200, stdout = vim.json.encode(response) })
      end)
    end,
  })
  local dedupe_done, dedupe_ok, dedupe_pull = false
  dedupe_client:get_pull_request(482, function(call_ok, value)
    dedupe_done, dedupe_ok, dedupe_pull = true, call_ok, value
  end)
  test.truthy(vim.wait(2000, function()
    return dedupe_done
  end, 10), "deduplicated check aggregation completes")
  test.truthy(dedupe_ok)
  test.eq(1, #dedupe_pull.statusCheckRollup, "GraphQL and REST copies of the same check run are deduplicated")
  test.eq("lint", dedupe_pull.statusCheckRollup[1].name)
  test.eq(0, #dedupe_pull.check_errors, "successful check sources do not create provider errors")

  local fixture_bin = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h") .. "/tests/bin"
  local original_path = vim.env.PATH
  vim.env.PATH = fixture_bin .. ":" .. original_path
  local production_client = github.new({
    repository = "acme/widget",
    token = "local-token",
    base_url = "http://fixture.local",
    cwd = vim.fn.getcwd(),
  })
  local transport_done, transport_ok, repository = false
  production_client:get_repository(function(call_ok, value)
    transport_done, transport_ok, repository = true, call_ok, value
  end)
  test.truthy(vim.wait(3000, function()
    return transport_done
  end, 10), "production curl transport completes through its executable boundary")
  vim.env.PATH = original_path
  test.truthy(transport_ok, "production curl transport succeeds: " .. vim.inspect(repository))
  test.eq("acme/widget", repository.full_name)
  test.eq("Bearer local-token", repository.authorization)
end
