return function(test)
  require("proud").setup({
    ui = {
      theme = "proud-e2e",
      themes = {
        ["proud-e2e"] = {
          extends = "proud-dark",
          groups = {
            ProudAccent = { bg = "#123456" },
          },
        },
      },
    },
  })
  test.eq("proud-e2e", require("proud.ui").current_theme(), "Proud setup selects UI framework themes")
  test.eq("#123456", require("proud.palette").groups().ProudAccent.bg, "Proud setup applies custom theme groups")
  require("proud.palette").setup({ theme = "proud-dark" })
  test.eq(2, vim.fn.exists(":Proud"), "Proud command is registered")
  vim.cmd("Proud demo")
  local buffer = require("proud.session").current.buffer
  test.truthy(vim.api.nvim_buf_is_valid(buffer))
  test.contains(vim.api.nvim_buf_get_name(buffer), "proud://prs")
  vim.cmd("silent! tabclose!")
  vim.cmd("Proud demo split")
  test.eq("branch_compare", require("proud.session").current.feature, "legacy split demo opens the pull request's diff page")
  vim.cmd("silent! tabclose!")

  local provider = require("proud.provider")
  local requests = {}
  local transport = function(request, callback)
    table.insert(requests, request)
    vim.schedule(function()
      if request.path:match("/pulls/6665$") then
        callback({
          code = 406,
          stdout = '{"message":"Sorry, the diff exceeded the maximum number of lines (20000)"}',
        })
      elseif request.path:match("/files$") then
        callback({
          code = 200,
          stdout = vim.json.encode({
            {
              filename = "src/retry.ts",
              status = "MODIFIED",
              patch = "@@ -1,1 +1,1 @@\n-old\n+new\n",
            },
          }),
        })
      else
        callback({
          code = 404,
          stdout = '{"message":"Not Found"}',
        })
      end
    end)
    return function() end
  end
  local done, patch_ok, patch = false
  provider.github({
    cwd = vim.fn.getcwd(),
    repository = "acme/widget",
    token = "test-token",
    transport = transport,
  }):get_patch(6665, function(ok, value)
    done, patch_ok, patch = true, ok, value
  end, { head_ref = "feat/retry", base_ref = "main" })
  vim.wait(1000, function()
    return done
  end, 10)
  test.truthy(done, "large diff fallback completes")
  test.truthy(patch_ok, "large diff fallback succeeds")
  test.contains(patch, "diff --git a/src/retry.ts b/src/retry.ts")
  test.eq(2, #requests, "fallback uses the pull request files endpoint")
  test.eq("/repos/acme/widget/pulls/6665", requests[1].path)
  test.contains(requests[2].path, "/repos/acme/widget/pulls/6665/files")
end
