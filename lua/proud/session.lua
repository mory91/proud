local loader = require("proud.loader")
local provider_module = require("proud.provider")

local M = {
  provider = nil,
  credentials_ready = false,
}

local function fail(message)
  vim.notify(message, vim.log.levels.ERROR, { title = "proud" })
end

local function is_current(state)
  local workspace = state and state.workspace
  return M.current
    and M.current.state == state
    and vim.api.nvim_buf_is_valid(M.current.buffer)
    and (not workspace or vim.api.nvim_tabpage_is_valid(workspace.tabpage))
end

function M.configure(options)
  M.options = options or {}
  M.credentials_ready = false
  M.current = nil
  M.provider = provider_module.default(M.options)
end

local function with_credentials(action)
  if M.credentials_ready then
    action()
    return
  end
  local credentials = loader.load("github_credentials")
  credentials.ensure({
    token = M.options and M.options.token,
    token_path = M.options and (M.options.token_path or M.options.token_file),
    credential = M.options and M.options.credential,
    repository = M.options and M.options.repository,
    base_url = M.options and M.options.base_url,
    cwd = M.options and M.options.cwd or vim.fn.getcwd(),
    validate = function(token, callback)
      local validation_provider = provider_module.default(vim.tbl_extend("force", M.options or {}, {
        token = token,
        token_file = nil,
      }))
      callback(true, {})
      vim.schedule(function()
        validation_provider:validate_access(function(ok, result)
          if not ok then
            fail(result and result.message or "GitHub credential validation failed")
          end
        end)
      end)
    end,
    on_success = function(token)
      M.options.token = token
      M.options.token_file = nil
      M.provider = provider_module.default(M.options)
      M.credentials_ready = true
    end,
  }, function(ok, result)
    if not ok then
      fail(result and result.message or "GitHub credential entry was cancelled")
      return
    end
    action()
  end)
end

function M.open_pull_requests(options)
  options = options or {}
  with_credentials(function()
    local feature = loader.load("pull_request_browser")
    local state = feature.create({}, options)
    local buffer = feature.open(state, {
      query = options.query,
      query_debounce_ms = M.options and M.options.query_debounce_ms or 250,
      description_debounce_ms = M.options and M.options.description_debounce_ms or 80,
      on_page = function(page, callback)
        M.provider:list_pull_requests_page(page.query, {
          limit = page.limit,
          after = page.after,
        }, callback)
      end,
      on_description = function(number, callback)
        M.provider:get_pull_request_description(number, callback)
      end,
      on_open = function(pull)
        if pull then
          M.open_overview(pull.number)
        end
      end,
    })
    M.current = { feature = "pull_request_browser", state = state, buffer = buffer }
  end)
end

function M.open_overview(number)
  with_credentials(function()
    local feature = loader.load("pull_request_overview")
    local state = feature.create({ number = number, title = "Pull request #" .. tostring(number) }, { loading = true })
    local buffer = feature.open(state, {
      on_diff = function(path)
        M.open_diff(number, path)
      end,
      on_review = function()
        M.open_review(state.pull)
      end,
    })
    M.current = { feature = "pull_request_overview", state = state, buffer = buffer }
    M.provider:get_pull_request(number, function(ok, pull)
      if not is_current(state) then
        return
      end
      if not ok then
        state.loading = false
        if state.refresh then
          state.refresh()
        end
        fail(pull.message)
        return
      end
      feature.hydrate(state, pull)
    end)
  end)
end

-- Opens the editable diff: checks out the PR branch in place and shows its
-- changed files (starting with `path` when given). Threads hydrate
-- independently. Git errors are shown in the scene as git reports them.
function M.open_diff(number, path)
  with_credentials(function()
    local name = "single_diff_threads"
    local feature = loader.load(name)
    local state = feature.create({ number = number, title = "Pull request #" .. tostring(number) }, {})
    local buffer = feature.open(state, {
      cwd = M.options and M.options.cwd or vim.fn.getcwd(),
      load = false,
    })
    M.current = { feature = name, state = state, buffer = buffer }
    M.provider:list_threads(number, function(thread_ok, threads)
      if M.current and M.current.state == state then
        feature.hydrate(state, { threads = thread_ok and threads or {} })
      end
    end)
    M.provider:get_pull_request(number, function(ok, pull)
      if not (M.current and M.current.state == state) then
        return
      end
      if not ok then
        state.status = "error"
        state.error = pull.message
        fail(pull.message)
        return
      end
      feature.hydrate(state, { pull = pull })
      feature.load(state, { path = path })
    end)
  end)
end

function M.open_compare(base, head)
  local git = provider_module.git({ cwd = M.options and M.options.cwd or nil })
  local feature = loader.load("branch_compare")
  local state = feature.create({
    base = base,
    head = head,
    ahead = 0,
    behind = 0,
    commits = {},
    files = {},
    loading = true,
  })
  local buffer = feature.open(state)
  M.current = { feature = "branch_compare", state = state, buffer = buffer }
  git:compare(base, head, function(ok, output)
    if not is_current(state) then
      return
    end
    if not ok then
      state.loading = false
      if state.refresh then
        state.refresh()
      end
      fail(output.message)
      return
    end
    local counts = vim.split(output[1] or "", "\t", { trimempty = true })
    local commits = {}
    for line in (output[2] or ""):gmatch("[^\n]+") do
      local sha, message = line:match("^(%x+)%s+(.+)$")
      table.insert(commits, { sha = sha or "", message = message or line })
    end
    local files = {}
    for line in (output[3] or ""):gmatch("[^\n]+") do
      local additions, deletions, path = line:match("^(%d+)%s+(%d+)%s+(.+)$")
      table.insert(files, {
        additions = tonumber(additions) or 0,
        deletions = tonumber(deletions) or 0,
        path = path or "",
        status = additions == "-" and "B" or "M",
      })
    end
    feature.hydrate(state, {
      base = base,
      head = head,
      behind = tonumber(counts[1]) or 0,
      ahead = tonumber(counts[2]) or 0,
      commits = commits,
      files = files,
    })
  end)
end

function M.open_help()
  local feature = loader.load("keymap_help")
  local state = feature.create()
  feature.toggle(state)
  M.help = state
end

function M.open_review(pull, options)
  options = options or {}
  local feature = loader.load("review_submission")
  local state = feature.create(pull, { event = options.event })
  local buffer = feature.open(state, {
    on_submit = function(event, body, callback)
      M.provider:submit_review(pull.number, event, body, callback)
    end,
    on_success = options.on_success,
  })
  M.current = { feature = "review_submission", state = state, buffer = buffer }
  return buffer, state
end

function M.demo(screen)
  local fixtures = require("proud.fixtures")
  screen = screen or "browser"
  if screen == "split" then
    screen = "single"
  end
  if screen == "browser" then
    local feature = loader.load("pull_request_browser")
    local state = feature.create(fixtures.pull_requests, {
      query = "is:open",
      display_query = "retry is:open",
    })
    local buffer = feature.open(state, {
      on_open = function(pull)
        if pull then
          local overview_feature = loader.load("pull_request_overview")
          local overview = vim.deepcopy(fixtures.overview)
          overview.number = pull.number
          overview.title = pull.title
          overview.author = pull.author and pull.author.login or pull.author
          overview.head_ref = pull.head_ref
          overview.base_ref = pull.base_ref
          overview.labels = pull.labels
          local overview_state = overview_feature.create(overview)
          local overview_buffer = overview_feature.open(overview_state, {
            on_diff = function()
              M.demo("single")
            end,
            on_review = function()
              M.demo("review")
            end,
          })
          M.current = {
            feature = "pull_request_overview",
            state = overview_state,
            buffer = overview_buffer,
          }
        end
      end,
    })
    M.current = { feature = "pull_request_browser", state = state, buffer = buffer }
    return
  end
  if screen == "overview" then
    local feature = loader.load("pull_request_overview")
    local state = feature.create(fixtures.overview)
    local buffer = feature.open(state, {
      on_diff = function()
        M.demo("single")
      end,
      on_review = function()
        M.demo("review")
      end,
    })
    M.current = { feature = "pull_request_overview", state = state, buffer = buffer }
    return
  end
  if screen == "single" then
    -- The editable diff needs a real repository: build one from the
    -- fixtures (base branch, PR branch, local origin) and remove it on exit.
    local fixture_repo = require("proud.fixture_repo")
    if not (M.demo_repo and vim.uv.fs_stat(M.demo_repo.work)) then
      local repo = fixture_repo.create()
      M.demo_repo = repo
      vim.api.nvim_create_autocmd("VimLeavePre", {
        once = true,
        callback = function()
          fixture_repo.remove(repo)
        end,
      })
    end
    local repo = M.demo_repo
    local feature = loader.load("single_diff_threads")
    local state = feature.create(fixtures.overview, fixtures.threads, { cwd = repo.work })
    local buffer = feature.open(state)
    M.current = { feature = "single_diff_threads", state = state, buffer = buffer, repo = repo }
    return
  end
  if screen == "compare" then
    local feature = loader.load("branch_compare")
    local state = feature.create(fixtures.compare)
    local buffer = feature.open(state)
    M.current = { feature = "branch_compare", state = state, buffer = buffer }
    return
  end
  if screen == "help" then
    M.open_help()
    return
  end
  if screen == "review" then
    local feature = loader.load("review_submission")
    local state = feature.create(fixtures.overview, {
      event = "COMMENT",
      body = "Use exponential backoff with jitter and keep retry limits configurable.",
    })
    local buffer = feature.open(state, {
      on_submit = function(event, body, callback)
        vim.schedule(function()
          callback(true, { id = 944, event = event, body = body })
        end)
      end,
    })
    M.current = { feature = "review_submission", state = state, buffer = buffer }
    return
  end
  error("Unknown Proud demo screen: " .. screen)
end

return M
