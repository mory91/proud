return function(test)
  local feature = require("proud.loader").load("github_credentials")
  local token_path = vim.fn.tempname()
  local validation_count = 0
  local success_token
  local state = feature.create({
    token_path = token_path,
    credential = false,
    validate = function(token, callback)
      validation_count = validation_count + 1
      vim.schedule(function()
        callback(token == "github_pat_valid", token == "github_pat_valid" and {} or {
          message = "HTTP 401: Token rejected",
        })
      end)
    end,
    on_success = function(token)
      success_token = token
    end,
  })

  local buffer, window = feature.open(state)
  test.truthy(vim.api.nvim_buf_is_valid(buffer))
  test.truthy(vim.api.nvim_win_is_valid(window))
  local config = vim.api.nvim_win_get_config(window)
  test.eq("editor", config.relative)
  test.eq(math.floor((vim.o.lines - config.height) / 2), config.row, "credential modal is vertically centered")
  test.eq(math.floor((vim.o.columns - config.width) / 2), config.col, "credential modal is horizontally centered")
  test.truthy(vim.api.nvim_buf_is_valid(state.prompt_buffer), "credential page owns an input buffer")
  test.truthy(vim.api.nvim_win_is_valid(state.prompt_window), "credential page owns an input window")
  local prompt_config = vim.api.nvim_win_get_config(state.prompt_window)
  test.eq("editor", prompt_config.relative)
  test.eq(1, prompt_config.height, "credential input is a one-line prompt window")
  test.eq(config.width, prompt_config.width)
  test.eq(config.col, prompt_config.col)
  test.eq(config.row + config.height + 1, prompt_config.row, "input window sits below the credential details")
  test.eq(state.prompt_window, vim.api.nvim_get_current_win(), "typing focus stays inside the credential page")
  test.eq(2, vim.wo[state.prompt_window].conceallevel, "credential input masks its contents")
  test.eq("nvic", vim.wo[state.prompt_window].concealcursor, "credential input stays masked in every mode")
  test.eq("<CR>", vim.fn.maparg("<CR>", "i", false, true).lhs, "credential page maps insert-mode submission")
  test.eq(false, vim.bo[state.prompt_buffer].undofile, "credential prompt never persists undo history")
  test.eq(-1, vim.bo[state.prompt_buffer].undolevels, "credential prompt cannot retain rejected tokens in undo history")

  vim.api.nvim_feedkeys("igithub_pat_invalid", "x", false)
  test.eq("github_pat_invalid", vim.api.nvim_buf_get_lines(state.prompt_buffer, 0, 1, false)[1])
  local concealed_characters = 0
  for column = 1, #"github_pat_invalid" do
    local concealed = vim.fn.synconcealed(1, column)
    if concealed[1] == 1 and concealed[2] == "*" then
      concealed_characters = concealed_characters + 1
    end
  end
  test.eq(#"github_pat_invalid", concealed_characters, "every entered token character is concealed in the page")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
  test.eq(1, validation_count, "enter validates text from the in-page prompt")
  test.truthy(vim.wait(2000, function()
    return state.error ~= nil
  end, 10), "invalid token returns to the modal with an error")
  test.contains(table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n"), "HTTP 401: Token rejected")
  test.truthy(vim.api.nvim_win_is_valid(window), "invalid token keeps the modal open")
  test.eq("", vim.api.nvim_buf_get_lines(state.prompt_buffer, 0, 1, false)[1], "rejected token is cleared from the page")

  vim.api.nvim_feedkeys("igithub_pat_valid", "x", false)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
  test.truthy(vim.wait(2000, function()
    return success_token ~= nil
  end, 10), "valid token completes credential setup")
  test.eq("github_pat_valid", success_token)
  test.truthy(not vim.api.nvim_win_is_valid(window), "successful credential modal closes")
  test.truthy(
    state.prompt_window == nil or not vim.api.nvim_win_is_valid(state.prompt_window),
    "successful credential input closes"
  )
  test.eq("github_pat_valid", feature.read_token(token_path))

  local opened = false
  local validated_again = false
  local reused
  local ensure_done = false
  feature.ensure({
    token_path = token_path,
    credential = false,
    validate = function(token, callback)
      validated_again = true
      callback(true, {})
    end,
    open_prompt = function()
      opened = true
    end,
  }, function(ok, token)
    ensure_done = true
    test.truthy(ok)
    reused = token
  end)
  test.truthy(ensure_done, "session credential cache completes immediately")
  test.eq("github_pat_valid", reused)
  test.truthy(not opened, "stored reusable credentials never reopen the prompt")
  test.truthy(not validated_again, "later screens reuse the validated session credential")

  feature.reset()
  local session = require("proud.session")
  local original_resolve_candidate = feature.resolve_candidate
  local resolve_options
  feature.resolve_candidate = function(options, callback)
    resolve_options = options
    return original_resolve_candidate(options, callback)
  end
  local listed_query
  local fake_client = {
    get_repository = function(_, callback)
      callback(true, { full_name = "acme/widget" })
    end,
    list_pull_requests = function(_, query, _, callback)
      listed_query = query
      callback(true, {
        {
          number = 482,
          title = "Credential gated pull request",
          user = { login = "sara-k" },
          state = "open",
          head = { ref = "feat/auth" },
          base = { ref = "main" },
          labels = {},
          files = {},
          commits = {},
          statusCheckRollup = {},
        },
      })
    end,
  }
  session.configure({
    kind = "github",
    repository = "acme/widget",
    token_path = token_path,
    credential = false,
    client = fake_client,
    cwd = vim.fn.getcwd(),
  })
  session.open_pull_requests({ query = "is:open" })
  test.truthy(vim.wait(2000, function()
    return session.current and session.current.feature == "pull_request_browser"
  end, 10), "saved credential opens the live pull request browser")
  test.eq("is:open", listed_query)
  test.truthy(session.credentials_ready)
  test.eq(token_path, resolve_options.token_path, "session preserves the configured reusable token path")
  test.eq(false, resolve_options.credential, "session preserves credential-helper configuration")
  feature.resolve_candidate = original_resolve_candidate
  vim.cmd("silent! tabclose!")
end
