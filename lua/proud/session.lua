local loader = require("proud.loader")
local provider_module = require("proud.provider")

local M = {
  provider = nil,
  credentials_ready = false,
}

local function repository()
  return M.options and M.options.cwd or vim.fn.getcwd()
end

-- Starts checking out the pull request in the background so the diff
-- opens without waiting on fetches. Failures stay silent here; the diff
-- retries and shows git's error.
-- Disabled with `background_checkout = false`.
local function prepare_checkout(pull)
  if M.options and M.options.background_checkout == false then
    return
  end
  if pull and pull.number and (pull.head_ref or "") ~= "" then
    require("proud.git").prepare_pull(repository(), pull)
  end
end

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
      on_commit = function(sha)
        M.open_diff(number, nil, sha)
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
      prepare_checkout(state.pull)
    end)
  end)
end

-- Opens a pull request's diff: the compare page for base...head with the
-- PR's threads. The branch is checked out in place (joining the overview's
-- background checkout); `path` opens that file first and `commit` selects
-- one commit's change. Git errors are shown in the diff pane as git
-- reports them.
function M.open_diff(number, path, commit)
  with_credentials(function()
    local name = "branch_compare"
    local feature = loader.load(name)
    -- The overview already has the branch names: start loading at once
    -- instead of requesting them again.
    local known = M.current
      and M.current.feature == "pull_request_overview"
      and M.current.state.pull
    known = known and known.number == number and (known.head_ref or "") ~= "" and known or nil
    local state = feature.create({
      pull = known or { number = number, title = "Pull request #" .. tostring(number) },
      cwd = repository(),
    })
    local buffer = feature.open(state, {
      path = path,
      commit = commit,
      load = known ~= nil,
    })
    M.current = { feature = name, state = state, buffer = buffer }
    M.provider:list_threads(number, function(thread_ok, threads)
      if M.current and M.current.state == state then
        feature.set_threads(state, thread_ok and threads or {})
      end
    end)
    M.provider:get_pull_request(number, function(ok, pull)
      if not (M.current and M.current.state == state) or known then
        return
      end
      if not ok then
        state.loading = false
        loader.load("diff_view").fail(state.diff, pull.message)
        return
      end
      feature.set_pull(state, pull)
      feature.load(state, { path = path, commit = commit })
    end)
  end)
end

-- Compares two local branches: checks out `head` in place and shows its
-- changes against `base`.
function M.open_compare(base, head)
  local feature = loader.load("branch_compare")
  local state = feature.create({ base = base, head = head, cwd = repository() })
  local buffer = feature.open(state)
  M.current = { feature = "branch_compare", state = state, buffer = buffer }
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

-- The editable diff needs a real repository: build one from the fixtures
-- (base branch, PR branch, local origin) once, and remove it on exit.
local function demo_repository()
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
  return M.demo_repo
end

-- Demo counterpart of prepare_checkout: after the overview has drawn,
-- build the fixture repository and start checking out its pull request.
local function demo_prepare_checkout()
  vim.schedule(function()
    local repo = demo_repository()
    require("proud.git").prepare_pull(repo.work, require("proud.fixtures").overview)
  end)
end

-- options (diff and compare): path, commit.
function M.demo(screen, options)
  options = options or {}
  local fixtures = require("proud.fixtures")
  screen = screen or "browser"
  -- Older names for the pull request diff, now the compare page.
  if screen == "split" or screen == "single" then
    screen = "diff"
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
            on_diff = function(path)
              M.demo("diff", { path = path })
            end,
            on_commit = function(sha)
              M.demo("diff", { commit = sha })
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
          demo_prepare_checkout()
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
      on_diff = function(path)
        M.demo("diff", { path = path })
      end,
      on_commit = function(sha)
        M.demo("diff", { commit = sha })
      end,
      on_review = function()
        M.demo("review")
      end,
    })
    M.current = { feature = "pull_request_overview", state = state, buffer = buffer }
    demo_prepare_checkout()
    return
  end
  if screen == "diff" then
    -- The pull request's diff: the compare page on the fixture repository,
    -- with the fixture threads.
    local repo = demo_repository()
    local feature = loader.load("branch_compare")
    local state = feature.create({ pull = fixtures.overview, threads = fixtures.threads, cwd = repo.work })
    local buffer = feature.open(state, options)
    M.current = { feature = "branch_compare", state = state, buffer = buffer, repo = repo }
    return
  end
  if screen == "compare" then
    local repo = demo_repository()
    local feature = loader.load("branch_compare")
    local state = feature.create({
      base = fixtures.overview.base_ref,
      head = fixtures.overview.head_ref,
      cwd = repo.work,
    })
    local buffer = feature.open(state, options)
    M.current = { feature = "branch_compare", state = state, buffer = buffer, repo = repo }
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
