local cache_module = require("proud.cache")
local util = require("proud.util")
local ffi_available, ffi = pcall(require, "ffi")
if ffi_available then
  pcall(ffi.cdef, "void *malloc(size_t size); void free(void *pointer);")
end

local M = {
  name = "github_api",
  api_version = "2022-11-28",
  user_agent = "proud-nvim/0.1",
}

local function schedule(callback, ...)
  local values = { ... }
  vim.schedule(function()
    callback(unpack(values))
  end)
end

local function flatten_pages(value)
  if type(value) ~= "table" then
    return {}
  end
  if value[1] and type(value[1]) == "table" and value[1][1] then
    local flattened = {}
    for _, page in ipairs(value) do
      for _, item in ipairs(page) do
        table.insert(flattened, item)
      end
    end
    return flattened
  end
  return value
end

function M.encode_component(value)
  return (tostring(value):gsub("[^%w%-._~]", function(character)
    return ("%%%02X"):format(string.byte(character))
  end))
end

function M.build_url(base_url, path, query)
  local url = tostring(base_url or "https://api.github.com"):gsub("/+$", "") .. (path or "")
  local keys = {}
  for key in pairs(query or {}) do
    table.insert(keys, key)
  end
  table.sort(keys)
  local parameters = {}
  for _, key in ipairs(keys) do
    local values = type(query[key]) == "table" and query[key] or { query[key] }
    for _, value in ipairs(values) do
      table.insert(parameters, M.encode_component(key) .. "=" .. M.encode_component(value))
    end
  end
  if #parameters > 0 then
    url = url .. "?" .. table.concat(parameters, "&")
  end
  return url
end

function M.parse_repository(remote)
  remote = util.trim(tostring(remote or "")):gsub("%.git$", "")
  local owner, repository = remote:match("@[^:]+:([^/]+)/([^/]+)$")
  if not owner then
    owner, repository = remote:match("://[^/]+/([^/]+)/([^/]+)$")
  end
  if not owner then
    owner, repository = remote:match("github%.com[:/]([^/]+)/([^/]+)$")
  end
  if owner and repository then
    return owner .. "/" .. repository
  end
  return nil
end

function M.is_diff_too_large(value)
  local message = type(value) == "table"
      and (value.message or value.body or value.stderr or value.stdout or "")
    or tostring(value or "")
  if type(message) == "table" then
    message = vim.json.encode(message)
  end
  message = tostring(message):lower()
  return message:find("maximum number of lines", 1, true) ~= nil
    or message:find("too_large", 1, true) ~= nil
end

function M.normalize_review_event(value)
  local event = tostring(value or ""):upper():gsub("[%s%-]", "_")
  if event == "COMMENT" or event == "APPROVE" or event == "REQUEST_CHANGES" then
    return event
  end
  return nil
end

local function format_duration_seconds(value)
  local seconds = math.max(0, math.floor(tonumber(value) or 0))
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  if hours > 0 then
    return ("%dh %02dm"):format(hours, minutes)
  end
  if minutes > 0 then
    return ("%dm %02ds"):format(minutes, seconds % 60)
  end
  return ("%ds"):format(seconds)
end

function M.check_duration(check)
  if type(check) ~= "table" then
    return ""
  end
  if type(check.duration) == "number" then
    return format_duration_seconds(check.duration)
  end
  local explicit = util.trim(tostring(check.duration or ""))
  if explicit ~= "" then
    return explicit
  end
  local started_at = util.parse_iso8601(check.started_at or check.startedAt)
  local completed_at = util.parse_iso8601(check.completed_at or check.completedAt)
  if not started_at or not completed_at or completed_at < started_at then
    return ""
  end
  return format_duration_seconds(completed_at - started_at)
end

local function check_identity(item, check)
  local database_id = item.database_id or item.databaseId
  if database_id ~= nil and database_id ~= "" then
    return "database:" .. tostring(database_id)
  end
  if type(item.id) == "number" then
    return "database:" .. tostring(item.id)
  end
  local name = check.name or ""
  local status = tostring(check.conclusion or check.state or ""):lower()
  local timestamp = tostring(
    item.started_at
      or item.startedAt
      or item.created_at
      or item.createdAt
      or ""
  )
  local url = tostring(item.target_url or item.targetUrl or item.details_url or item.detailsUrl or item.url or "")
  return table.concat({ name, status, check.duration or "", timestamp, url }, "\0")
end

local function build_patch_from_files_tables(files)
  local chunks = {}
  for _, file in ipairs(flatten_pages(files)) do
    if type(file) == "table" then
      local path = file.filename or file.path or ""
      if path ~= "" then
        local status = tostring(file.status or "MODIFIED"):upper()
        local old_path = file.previous_filename or file.previousFilename or file.previous_path or file.old_path or path
        local old_header = status == "ADDED" and "/dev/null" or "a/" .. old_path
        local new_header = status == "DELETED" and "/dev/null" or "b/" .. path
        local header = ("diff --git a/%s b/%s\n--- %s\n+++ %s"):format(
          old_path,
          path,
          old_header,
          new_header
        )
        table.insert(chunks, file.patch and file.patch ~= "" and (header .. "\n" .. file.patch) or header)
      end
    end
  end
  return table.concat(chunks, "\n")
end

function M.build_patch_from_files(files)
  if not ffi_available then
    return build_patch_from_files_tables(files)
  end
  files = flatten_pages(files)
  local total = 0
  local count = 0
  for _, file in ipairs(files) do
    if type(file) == "table" then
      local path = file.filename or file.path or ""
      if path ~= "" then
        local status = tostring(file.status or "MODIFIED"):upper()
        local old_path = file.previous_filename or file.previousFilename or file.previous_path or file.old_path or path
        local old_header = status == "ADDED" and "/dev/null" or "a/" .. old_path
        local new_header = status == "DELETED" and "/dev/null" or "b/" .. path
        local patch = file.patch or ""
        total = total
          + #"diff --git a/"
          + #old_path
          + #" b/"
          + #path
          + #"\n--- "
          + #old_header
          + #"\n+++ "
          + #new_header
          + (patch ~= "" and #"\n" + #patch or 0)
        count = count + 1
      end
    end
  end
  if count == 0 then
    return ""
  end
  total = total + count - 1
  local allocation = ffi.C.malloc(total)
  if allocation == nil then
    return build_patch_from_files_tables(files)
  end
  local output = ffi.cast("unsigned char*", allocation)
  local offset = 0
  local function append(value)
    ffi.copy(output + offset, value, #value)
    offset = offset + #value
  end
  local index = 0
  for _, file in ipairs(files) do
    if type(file) == "table" then
      local path = file.filename or file.path or ""
      if path ~= "" then
        if index > 0 then
          append("\n")
        end
        local status = tostring(file.status or "MODIFIED"):upper()
        local old_path = file.previous_filename or file.previousFilename or file.previous_path or file.old_path or path
        local old_header = status == "ADDED" and "/dev/null" or "a/" .. old_path
        local new_header = status == "DELETED" and "/dev/null" or "b/" .. path
        local patch = file.patch or ""
        append("diff --git a/")
        append(old_path)
        append(" b/")
        append(path)
        append("\n--- ")
        append(old_header)
        append("\n+++ ")
        append(new_header)
        if patch ~= "" then
          append("\n")
          append(patch)
        end
        index = index + 1
      end
    end
  end
  local result = ffi.string(output, total)
  ffi.C.free(allocation)
  return result
end

local function sorted_headers(headers)
  local names = {}
  for name in pairs(headers or {}) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

local function escape_curl(value)
  return tostring(value):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "\\r"):gsub("\n", "\\n")
end

function M.curl_config(request)
  local lines = {
    "silent",
    "show-error",
    ('url = "%s"'):format(escape_curl(request.url)),
    ('request = "%s"'):format(escape_curl(request.method or "GET")),
  }
  for _, name in ipairs(sorted_headers(request.headers)) do
    table.insert(lines, ('header = "%s: %s"'):format(escape_curl(name), escape_curl(request.headers[name])))
  end
  if request.body ~= nil then
    table.insert(lines, ('data = "%s"'):format(escape_curl(request.body)))
  end
  table.insert(lines, 'write-out = "\\n%{http_code}"')
  return table.concat(lines, "\n") .. "\n"
end

function M.transport_command()
  return { "curl", "--silent", "--show-error", "--config", "-" }
end

local function parse_transport_response(response, raw)
  response = response or {}
  local stdout = response.stdout or ""
  local body, written_code = stdout:match("^(.*)\n(%d+)\r?\n?$")
  if not body then
    body = stdout
  end
  local code = tonumber(written_code) or tonumber(response.code) or 0
  local decoded = nil
  if body ~= "" then
    local ok, value = pcall(vim.json.decode, body)
    if ok then
      decoded = value
    end
  end
  if code >= 200 and code < 300 then
    return true, raw and body or (decoded or {})
  end
  local message = type(decoded) == "table" and decoded.message or response.stderr or body or "GitHub API request failed"
  return false, {
    code = code,
    message = util.trim(tostring(message)),
    body = decoded or body,
    too_large = M.is_diff_too_large({ message = message, body = body }),
  }
end

function M.default_transport(options)
  options = options or {}
  return function(request, callback)
    local completed = vim.system(M.transport_command(), {
      text = true,
      stdin = M.curl_config(request),
      cwd = options.cwd,
    }, function(result)
      schedule(callback, result)
    end)
    return function()
      pcall(completed.kill, completed, 15)
    end
  end
end

local function environment_token()
  local names = { "PROUD_GITHUB_TOKEN", "GITHUB_TOKEN", "GH_TOKEN" }
  for _, name in ipairs(names) do
    local value = vim.env[name]
    if value and value ~= "" then
      return value
    end
  end
  return nil
end

local function read_token_file(path)
  if not path or path == "" then
    return nil
  end
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local value = file:read("*a")
  file:close()
  value = util.trim(value or "")
  return value ~= "" and value or nil
end

local function host_for_credentials(base_url)
  local host = tostring(base_url or "https://api.github.com"):match("^[^:]+://([^/:]+)")
  if host == "api.github.com" then
    return "github.com"
  end
  return host or "github.com"
end

local function credential_token(options, callback)
  local host = options.git_host or host_for_credentials(options.base_url)
  local input = ("protocol=https\nhost=%s\n\n"):format(host)
  vim.system({ "git", "credential", "fill" }, {
    text = true,
    stdin = input,
    cwd = options.cwd,
  }, function(result)
    if result.code ~= 0 then
      schedule(callback, nil)
      return
    end
    local token = tostring(result.stdout or ""):match("\npassword=([^\r\n]+)")
    schedule(callback, token)
  end)
end

function M.resolve_token(options, callback)
  options = options or {}
  if type(options.token) == "function" then
    options.token(callback)
    return
  end
  local token = options.token
    or environment_token()
    or read_token_file(options.token_file)
  if token then
    schedule(callback, token)
    return
  end
  credential_token(options, callback)
end

local function parse_remote_repository(remote)
  return M.parse_repository(remote)
end

function M.resolve_repository(options, callback)
  options = options or {}
  local repository = options.repository
    or vim.env.PROUD_GITHUB_REPOSITORY
    or vim.env.GITHUB_REPOSITORY
  if repository and repository ~= "" then
    schedule(callback, repository)
    return
  end
  vim.system({ "git", "remote", "get-url", "origin" }, {
    text = true,
    cwd = options.cwd,
  }, function(result)
    local resolved = result.code == 0 and parse_remote_repository(result.stdout) or nil
    schedule(callback, resolved)
  end)
end

function M.new(options)
  options = options or {}
  local client = {
    base_url = options.base_url or "https://api.github.com",
    repository = options.repository,
    cwd = options.cwd or vim.fn.getcwd(),
    page_size = options.page_size or 100,
    max_pages = options.max_pages or 100,
    cache = cache_module.new({ max_items = options.cache_items or 128 }),
    transport = options.transport,
    token = options.token,
    token_file = options.token_file,
    git_host = options.git_host,
  }
  client.transport = client.transport or M.default_transport({ cwd = client.cwd })

  function client:resolve_repository(callback)
    M.resolve_repository(self, callback)
  end

  local function repository_path(suffix)
    local repository = assert(client.repository, "GitHub repository is not configured")
    return "/repos/" .. repository .. (suffix or "")
  end

  local function cache_key(request, url)
    return table.concat({ request.method or "GET", url }, "\0")
  end

  function client:request(specification, callback)
    local request = vim.deepcopy(specification or {})
    request.method = request.method or "GET"
    request.url = M.build_url(self.base_url, request.path, request.query)
    request.headers = vim.tbl_extend("force", {
      Accept = request.accept or "application/vnd.github+json",
    }, request.headers or {})
    request.headers["X-GitHub-Api-Version"] = self.api_version or M.api_version
    request.headers["User-Agent"] = M.user_agent
    if type(request.body) == "table" then
      request.body = vim.json.encode(request.body)
    end
    local key = cache_key(request, request.url)
    if request.method == "GET" and not request.skip_cache then
      local cached = self.cache:get(key)
      if cached ~= nil then
        schedule(callback, true, vim.deepcopy(cached))
        return function() end
      end
    end
    local finished = false
    local cancel = nil
    local function finish(ok, value)
      if finished then
        return
      end
      finished = true
      if ok and request.method == "GET" and not request.skip_cache then
        self.cache:set(key, vim.deepcopy(value))
      end
      schedule(callback, ok, value)
    end
    M.resolve_token({
      token = self.token,
      token_file = self.token_file,
      base_url = self.base_url,
      git_host = self.git_host,
      cwd = self.cwd,
    }, function(token)
      if token then
        request.headers.Authorization = "Bearer " .. token
      end
      cancel = self.transport(request, function(response)
        local ok, value = parse_transport_response(response, request.raw)
        finish(ok, value)
      end)
    end)
    return function()
      if cancel then
        cancel()
      end
    end
  end

  function client:request_json(specification, callback)
    return self:request(specification, callback)
  end

  function client:paginate(path, query, callback)
    local items = {}
    local page = 1
    local function load_page()
      if page > self.max_pages then
        callback(false, { code = 502, message = "GitHub pagination exceeded the supported page limit" })
        return
      end
      local page_query = vim.tbl_extend("force", query or {}, {
        page = page,
        per_page = self.page_size,
      })
      self:request_json({ method = "GET", path = path, query = page_query }, function(ok, value)
        if not ok then
          callback(false, value)
          return
        end
        local page_items = value
        if type(value) == "table" then
          page_items = value.items or value.check_runs or value.statuses or value
        end
        if type(page_items) ~= "table" then
          callback(false, { code = 502, message = "GitHub returned a non-list pagination payload" })
          return
        end
        for _, item in ipairs(page_items) do
          table.insert(items, item)
        end
        local total_count = type(value) == "table" and tonumber(value.total_count) or nil
        if (total_count and #items >= total_count) or #page_items < self.page_size then
          callback(true, items)
          return
        end
        page = page + 1
        load_page()
      end)
    end
    load_page()
  end

  function client:list_pull_requests_page(query, limit, after, callback)
    self:resolve_repository(function(repository)
      if not repository then
        callback(false, { code = 0, message = "Could not resolve the GitHub repository from git remote origin" })
        return
      end
      self.repository = repository
      local search = tostring(query or "is:open"):gsub("^%s+", ""):gsub("%s+$", "")
      if search == "" then
        search = "is:open"
      end
      local has_type = search:find("type:pr", 1, true) ~= nil
      local has_repository = search:find("repo:", 1, true) ~= nil
      if not has_type and not has_repository then
        search = "type:pr repo:" .. repository .. " " .. search
      elseif not has_type then
        search = "type:pr " .. search
      elseif not has_repository then
        search = search:gsub("^(type:pr)%s+", "%1 repo:" .. repository .. " ", 1)
      end
      local graphql_query = [=[
query ProudPullRequests($query: String!, $first: Int!, $after: String) {
  search(query: $query, type: ISSUE, first: $first, after: $after) {
    issueCount
    pageInfo {
      hasNextPage
      endCursor
    }
    nodes {
      ... on PullRequest {
        number
        title
        url
        state
        createdAt
        author { login }
        headRefName
        baseRefName
        headRefOid
        isDraft
        reviewDecision
        additions
        deletions
        labels(first: 100) { nodes { name } }
        reviewThreads { totalCount }
        reviewRequests(first: 20) {
          nodes {
            requestedReviewer {
              ... on User { login }
              ... on Team { name }
            }
          }
        }
        latestReviews(first: 20) {
          nodes {
            author { login }
            state
            submittedAt
          }
        }
      }
    }
  }
}
]=]
      local variables = {
        query = search,
        first = math.max(1, math.min(tonumber(limit) or 50, 100)),
      }
      if after and after ~= "" then
        variables.after = after
      end
      self:request_json({
        method = "POST",
        path = "/graphql",
        body = {
          query = graphql_query,
          variables = variables,
        },
      }, function(ok, value)
        if not ok then
          callback(false, value)
          return
        end
        local errors = type(value) == "table" and value.errors
        if type(errors) == "table" and #errors > 0 then
          callback(false, {
            code = value.code or 502,
            message = errors[1].message or "GitHub GraphQL request failed",
            body = value,
          })
          return
        end
        local search_result = type(value) == "table"
          and type(value.data) == "table"
          and value.data.search
        if type(search_result) ~= "table" or type(search_result.nodes) ~= "table" then
          callback(false, {
            code = 502,
            message = "GitHub GraphQL returned an unexpected search payload",
            body = value,
          })
          return
        end
        local page_info = type(search_result.pageInfo) == "table" and search_result.pageInfo or {}
        callback(true, {
          items = search_result.nodes,
          total_count = tonumber(search_result.issueCount) or #search_result.nodes,
          has_next_page = page_info.hasNextPage == true,
          next_cursor = page_info.hasNextPage == true and page_info.endCursor or nil,
        })
      end)
    end)
  end

  function client:list_pull_requests(query, limit, callback)
    self:list_pull_requests_page(query, limit, nil, function(ok, result)
      callback(ok, ok and result.items or result)
    end)
  end

  function client:get_pull_request_description(number, callback)
    self:resolve_repository(function(repository)
      if not repository then
        callback(false, { code = 0, message = "Could not resolve the GitHub repository from git remote origin" })
        return
      end
      self.repository = repository
      local owner, name = repository:match("^([^/]+)/([^/]+)$")
      if not owner or not name then
        callback(false, { code = 502, message = "GitHub repository must use the owner/name form" })
        return
      end
      local graphql_query = [=[
query ProudPullRequestDescription($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      body
    }
  }
}
]=]
      self:request_json({
        method = "POST",
        path = "/graphql",
        body = {
          query = graphql_query,
          variables = {
            owner = owner,
            name = name,
            number = math.floor(tonumber(number) or 0),
          },
        },
      }, function(ok, value)
        if not ok then
          callback(false, value)
          return
        end
        local errors = type(value) == "table" and value.errors
        if type(errors) == "table" and #errors > 0 then
          callback(false, {
            code = value.code or 502,
            message = errors[1].message or "GitHub GraphQL request failed",
            body = value,
          })
          return
        end
        local pull = type(value) == "table"
          and type(value.data) == "table"
          and type(value.data.repository) == "table"
          and value.data.repository.pullRequest
        if type(pull) ~= "table" then
          callback(false, {
            code = 502,
            message = "GitHub GraphQL returned an unexpected pull request description payload",
            body = value,
          })
          return
        end
        callback(true, type(pull.body) == "string" and pull.body or "")
      end)
    end)
  end

  function client:get_pull_request_checks(number, callback)
    local owner, name = tostring(self.repository or ""):match("^([^/]+)/([^/]+)$")
    if not owner or not name then
      callback(false, { code = 502, message = "GitHub repository must use the owner/name form" })
      return
    end
    local graphql_query = [=[
query ProudPullRequestChecks($owner: String!, $name: String!, $number: Int!, $first: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      statusCheckRollup {
        contexts(first: $first, after: $after) {
          nodes {
            __typename
            ... on CheckRun {
              id
              databaseId
              name
              status
              conclusion
              startedAt
              completedAt
              detailsUrl
            }
            ... on StatusContext {
              id
              context
              state
              createdAt
              updatedAt
              targetUrl
            }
          }
          pageInfo {
            hasNextPage
            endCursor
          }
        }
      }
    }
  }
}
]=]
    local items = {}
    local function load_page(after)
      self:request_json({
        method = "POST",
        path = "/graphql",
        body = {
          query = graphql_query,
          variables = {
            owner = owner,
            name = name,
            number = math.floor(tonumber(number) or 0),
            first = math.max(1, math.min(self.page_size, 100)),
            after = after,
          },
        },
      }, function(ok, value)
        if not ok then
          callback(false, value)
          return
        end
        local errors = type(value) == "table" and value.errors
        if type(errors) == "table" and #errors > 0 then
          callback(false, {
            code = value.code or 502,
            message = errors[1].message or "GitHub GraphQL request failed",
            body = value,
          })
          return
        end
        local pull = type(value) == "table"
          and type(value.data) == "table"
          and type(value.data.repository) == "table"
          and value.data.repository.pullRequest
        local contexts = type(pull) == "table"
          and type(pull.statusCheckRollup) == "table"
          and pull.statusCheckRollup.contexts
        if type(pull) ~= "table" or type(contexts) ~= "table" then
          callback(false, {
            code = 502,
            message = "GitHub GraphQL returned an unexpected pull request checks payload",
            body = value,
          })
          return
        end
        for _, item in ipairs(type(contexts.nodes) == "table" and contexts.nodes or {}) do
          table.insert(items, item)
        end
        local page_info = type(contexts.pageInfo) == "table" and contexts.pageInfo or {}
        if page_info.hasNextPage == true and page_info.endCursor then
          load_page(page_info.endCursor)
          return
        end
        callback(true, items)
      end)
    end
    load_page(nil)
  end

  function client:list_pull_request_files(number, callback)
    self:paginate(repository_path(("/pulls/%d/files"):format(number)), {}, callback)
  end

  function client:list_pull_request_commits(number, callback)
    self:paginate(repository_path(("/pulls/%d/commits"):format(number)), {}, callback)
  end

  function client:list_review_comments(number, callback)
    self:paginate(repository_path(("/pulls/%d/comments"):format(number)), {}, callback)
  end

  function client:list_pull_request_reviews(number, callback)
    self:paginate(repository_path(("/pulls/%d/reviews"):format(number)), {}, callback)
  end

  function client:list_issue_comments(number, callback)
    self:paginate(repository_path(("/issues/%d/comments"):format(number)), {}, callback)
  end

  function client:list_check_runs(ref, callback)
    self:paginate(repository_path(("/commits/%s/check-runs"):format(M.encode_component(ref))), {}, callback)
  end

  function client:list_commit_statuses(ref, callback)
    self:request_json({
      method = "GET",
      path = repository_path(("/commits/%s/status"):format(M.encode_component(ref))),
    }, function(ok, value)
      callback(ok, ok and (value.statuses or {}) or value)
    end)
  end

  function client:get_repository(callback)
    self:resolve_repository(function(repository)
      if not repository then
        callback(false, { code = 0, message = "Could not resolve the GitHub repository from git remote origin" })
        return
      end
      self.repository = repository
      self:request_json({ method = "GET", path = "/repos/" .. repository }, callback)
    end)
  end

  function client:get_pull_request(number, callback)
    self:request_json({ method = "GET", path = repository_path(("/pulls/%d"):format(number)) }, function(ok, pull)
      if not ok then
        callback(false, pull)
        return
      end
      local head_ref = type(pull.head) == "table" and pull.head.sha or nil
      local merge_ref = pull.merge_commit_sha
      if type(head_ref) ~= "string" or head_ref == "" then
        head_ref = nil
      end
      if type(merge_ref) ~= "string" or merge_ref == "" then
        merge_ref = nil
      end
      local check_refs = {}
      if head_ref then
        table.insert(check_refs, { key = "head", ref = head_ref })
      end
      if merge_ref and merge_ref ~= head_ref then
        table.insert(check_refs, { key = "merge", ref = merge_ref })
      end
      local remaining = 6 + #check_refs * 2
      local results = {}
      local errors = {}
      local function complete(name)
        return function(call_ok, value)
          if call_ok then
            results[name] = value or {}
          else
            results[name] = {}
            table.insert(errors, {
              source = name,
              code = value and value.code,
              message = value and value.message or "GitHub request failed",
            })
          end
          remaining = remaining - 1
          if remaining == 0 then
            local checks = {}
            local seen = {}
            local function add_check(item, check)
              local identity = check_identity(item, check)
              if not seen[identity] then
                seen[identity] = true
                table.insert(checks, check)
              end
            end
            for _, item in ipairs(results.graphql_checks or {}) do
              add_check(item, {
                name = item.name or item.context or "check",
                conclusion = item.conclusion,
                state = item.state or item.status,
                duration = M.check_duration(item),
                target_url = item.target_url or item.targetUrl or item.details_url or item.detailsUrl,
              })
            end
            for _, source in ipairs(check_refs) do
              local prefix = source.key == "head" and "" or source.key .. "_"
              for _, item in ipairs(results[prefix .. "check_runs"] or {}) do
                add_check(item, {
                  name = item.name or "check",
                  conclusion = item.conclusion,
                  status = item.status,
                  duration = M.check_duration(item),
                  target_url = item.target_url or item.details_url or item.url,
                })
              end
              for _, item in ipairs(results[prefix .. "statuses"] or {}) do
                add_check(item, {
                  name = item.context or "status",
                  state = item.state,
                  duration = "",
                  target_url = item.target_url or item.url,
                })
              end
            end
            pull.files = results.files
            pull.commits = results.commits
            pull.statusCheckRollup = checks
            pull.check_errors = errors
            pull.reviews = results.reviews
            pull.review_comments = results.review_comments
            pull.comments = results.issue_comments
            callback(true, pull)
          end
        end
      end
      self:list_pull_request_files(number, complete("files"))
      self:list_pull_request_commits(number, complete("commits"))
      self:list_pull_request_reviews(number, complete("reviews"))
      self:list_review_comments(number, complete("review_comments"))
      self:list_issue_comments(number, complete("issue_comments"))
      self:get_pull_request_checks(number, complete("graphql_checks"))
      for _, source in ipairs(check_refs) do
        local prefix = source.key == "head" and "" or source.key .. "_"
        self:list_check_runs(source.ref, complete(prefix .. "check_runs"))
        self:list_commit_statuses(source.ref, complete(prefix .. "statuses"))
      end
    end)
  end

  function client:get_pull_request_diff(number, callback)
    self:request({
      method = "GET",
      path = repository_path(("/pulls/%d"):format(number)),
      accept = "application/vnd.github.v3.diff",
      raw = true,
      skip_cache = true,
    }, callback)
  end

  function client:post_issue_comment(number, body, callback)
    self:request({
      method = "POST",
      path = repository_path(("/issues/%d/comments"):format(number)),
      body = { body = body },
      skip_cache = true,
    }, callback)
  end

  function client:submit_pull_request_review(number, event, body, callback)
    local normalized_event = M.normalize_review_event(event)
    if not normalized_event then
      vim.schedule(function()
        callback(false, {
          code = 0,
          message = "Review event must be comment, approve, or request changes",
        })
      end)
      return function() end
    end
    local normalized_body = tostring(body or "")
    if normalized_event ~= "APPROVE" and util.trim(normalized_body) == "" then
      vim.schedule(function()
        callback(false, {
          code = 0,
          message = "A review body is required for comment and request changes",
        })
      end)
      return function() end
    end
    return self:request({
      method = "POST",
      path = repository_path(("/pulls/%d/reviews"):format(number)),
      body = {
        event = normalized_event,
        body = normalized_body,
      },
      skip_cache = true,
    }, callback)
  end

  function client:get_authenticated_user(callback)
    self:request_json({ method = "GET", path = "/user" }, callback)
  end

  return client
end

return M
