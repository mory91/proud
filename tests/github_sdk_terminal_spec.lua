local github = require("proud.loader").load("github_api")
local replies = {
  ["/repos/acme/widget/pulls/482"] = {
    number = 482,
    title = "API terminal smoke test",
    user = { login = "sara-k" },
    head = { ref = "feat/checks", sha = "head-sha" },
    merge_commit_sha = "merge-sha",
    base = { ref = "main" },
    state = "open",
  },
  ["/repos/acme/widget/pulls/482/files"] = {
    { filename = "retry.ts", status = "MODIFIED", additions = 2, deletions = 1 },
  },
  ["/repos/acme/widget/pulls/482/commits"] = {
    { sha = "commit-sha", commit = { message = "Add checks" } },
  },
  ["/repos/acme/widget/commits/head-sha/check-runs"] = {
    total_count = 0,
    check_runs = {},
  },
  ["/repos/acme/widget/commits/head-sha/status"] = { statuses = {} },
  ["/repos/acme/widget/commits/merge-sha/check-runs"] = {
    total_count = 0,
    check_runs = {},
  },
  ["/repos/acme/widget/commits/merge-sha/status"] = { statuses = {} },
  ["/repos/acme/widget/pulls/482/reviews"] = {},
  ["/repos/acme/widget/issues/482/comments"] = {},
}
local client = github.new({
  repository = "acme/widget",
  token = "terminal-token",
  transport = function(request, callback)
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
                        databaseId = 1,
                        name = "lint",
                        status = "COMPLETED",
                        conclusion = "SUCCESS",
                        startedAt = "2026-10-18T12:00:00Z",
                        completedAt = "2026-10-18T12:00:18Z",
                      },
                      {
                        __typename = "CheckRun",
                        databaseId = 2,
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
                    pageInfo = { hasNextPage = false },
                  },
                },
              },
            },
          },
        }
      end
      callback({
        code = 200,
        stdout = vim.json.encode(response),
      })
    end)
  end,
})

client:get_pull_request(482, function(ok, pull)
  local checks = ok and pull.statusCheckRollup or {}
  local overview = ok and require("proud.loader").load("pull_request_overview").create(pull) or nil
  local check_node = overview and require("proud.components.tree").find(overview.sidebar, "checks")
  local passed = ok
    and pull.number == 482
    and #checks == 3
    and checks[1].name == "lint"
    and checks[2].name == "e2e / robot-studio"
    and checks[3].name == "preview"
    and check_node ~= nil
    and #check_node.children == 3
  vim.api.nvim_echo({ { passed and "GITHUB_SDK_TERMINAL_OK" or "GITHUB_SDK_TERMINAL_FAIL" } }, false, {})
end)
