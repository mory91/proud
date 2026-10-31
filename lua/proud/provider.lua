local github_sdk = require("proud.github")
local util = require("proud.util")

local M = {}

local function real_value(value)
  if value == nil or value == vim.NIL or type(value) == "userdata" then
    return nil
  end
  return value
end

local function text_value(value, fallback)
  value = real_value(value)
  if type(value) == "string" then
    return value
  end
  if type(value) == "number" then
    return tostring(value)
  end
  return fallback
end

local function number_value(value, fallback)
  return tonumber(real_value(value)) or fallback
end

local function boolean_value(value, fallback)
  value = real_value(value)
  if value == nil then
    return fallback
  end
  return value == true
end

local function list_value(value)
  value = real_value(value)
  return type(value) == "table" and value or {}
end

local function connection_items(value)
  value = real_value(value)
  if type(value) ~= "table" then
    return {}
  end
  local nodes = real_value(value.nodes)
  if type(nodes) == "table" then
    return nodes
  end
  local edges = real_value(value.edges)
  if type(edges) == "table" then
    local items = {}
    for _, edge in ipairs(edges) do
      local node = type(edge) == "table" and real_value(edge.node) or nil
      if node ~= nil then
        table.insert(items, node)
      end
    end
    return items
  end
  return value
end

local function first_value(...)
  for index = 1, select("#", ...) do
    local value = real_value((select(index, ...)))
    if value ~= nil then
      return value
    end
  end
  return nil
end

local function schedule(callback, ok, value)
  vim.schedule(function()
    callback(ok, value)
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

local function actor_name(value)
  value = real_value(value)
  if type(value) == "table" then
    return text_value(first_value(value.login, value.name, value.username), "")
  end
  return text_value(value, "")
end

local function review_state(value)
  local state = text_value(value, ""):lower():gsub("[%s%-]", "_")
  if state == "" or state == "review_required" or state == "requested" then
    return "pending"
  end
  return state
end

local function normalize_review(value, options)
  if type(value) ~= "table" then
    return nil
  end
  local requested = real_value(value.requestedReviewer)
  local author = actor_name(first_value(value.author, value.user, requested, value.login))
  local timestamp = real_value(first_value(value.submittedAt, value.submitted_at, value.createdAt, value.created_at))
  return {
    id = text_value(first_value(value.id, value.databaseId, value.node_id, value.nodeId), nil),
    login = author,
    state = review_state(first_value(value.state, value.review_state, "pending")),
    age = timestamp and util.relative_time(timestamp, options) or text_value(value.age, ""),
    body = text_value(first_value(value.body, value.message), ""),
  }
end

local function normalize_comment(value, options, source_kind)
  if type(value) ~= "table" then
    return nil
  end
  local timestamp = real_value(first_value(value.created_at, value.createdAt, value.submittedAt))
  local comment_kind = text_value(value.kind, source_kind or "comment")
  local reply_value = real_value(first_value(value.reply_to_id, value.replyToId))
  local reply_kind = text_value(value.reply_to_kind, nil)
  if reply_value ~= nil and reply_kind == nil then
    reply_kind = comment_kind
  end
  if reply_value == nil then
    reply_value = real_value(first_value(value.in_reply_to_id, value.inReplyToId))
    reply_kind = reply_value ~= nil and comment_kind or nil
  end
  if reply_value == nil then
    reply_value = real_value(first_value(value.pull_request_review_id, value.pullRequestReviewId, value.review_id, value.reviewId))
    reply_kind = reply_value ~= nil and "review" or nil
  end
  if reply_value == nil then
    reply_value = real_value(first_value(value.parent_id, value.parentId))
    reply_kind = reply_value ~= nil and (source_kind or "comment") or nil
  end
  return {
    id = text_value(first_value(value.id, value.databaseId, value.node_id, value.nodeId), nil),
    reply_to_id = text_value(reply_value, nil),
    reply_to_kind = reply_kind,
    author = actor_name(first_value(value.user, value.author, value.login)),
    age = timestamp and util.relative_time(timestamp, options) or text_value(value.age, ""),
    body = text_value(first_value(value.body, value.message), ""),
    kind = comment_kind,
  }
end

function M.normalize_checks(value)
  local checks = {}
  local items = list_value(value)
  if type(items.check_runs) == "table" then
    items = items.check_runs
  elseif type(items.statuses) == "table" then
    items = items.statuses
  end
  for _, item in ipairs(flatten_pages(items)) do
    if type(item) == "table" then
      local raw_status = text_value(first_value(item.conclusion, item.state, item.status), "")
      local normalized_status = raw_status:lower()
      local status = "pending"
      if normalized_status == "success" or normalized_status == "pass" or normalized_status == "neutral" or normalized_status == "skipped" then
        status = "pass"
      elseif normalized_status == "failure" or normalized_status == "fail" or normalized_status == "cancelled" or normalized_status == "timed_out" or normalized_status == "action_required" then
        status = "fail"
      end
      table.insert(checks, {
        name = text_value(first_value(item.name, item.context, item.job_name), "check"),
        status = status,
        duration = text_value(github_sdk.check_duration(item), ""),
      })
    end
  end
  return checks
end

function M.normalize_pull_request(value, options)
  local pull = type(value) == "table" and vim.deepcopy(value) or {}
  local author = first_value(pull.author, pull.user)
  if type(author) == "table" then
    pull.author = text_value(first_value(author.login, author.name), "unknown")
  else
    pull.author = text_value(author, "unknown")
  end
  local milestone = real_value(pull.milestone)
  if type(milestone) == "table" then
    milestone = first_value(milestone.title, milestone.name)
  end
  milestone = text_value(milestone, nil)
  pull.milestone = milestone ~= "" and milestone or nil
  local labels = {}
  local seen_labels = {}
  for _, label in ipairs(connection_items(pull.labels)) do
    local label_name = type(label) == "table" and first_value(label.name, label) or label
    label_name = text_value(label_name, nil)
    if label_name and label_name ~= "" and not seen_labels[label_name] then
      seen_labels[label_name] = true
      table.insert(labels, label_name)
    end
  end
  pull.labels = labels
  pull.title = text_value(pull.title, "Untitled pull request")
  pull.number = number_value(pull.number, 0)
  pull.additions = math.max(0, number_value(pull.additions, 0))
  pull.deletions = math.max(0, number_value(pull.deletions, 0))
  local review_threads = real_value(first_value(pull.reviewThreads, pull.review_threads))
  local thread_count = first_value(
    pull.threads,
    type(review_threads) == "table" and first_value(review_threads.totalCount, review_threads.total_count) or nil
  )
  pull.threads = math.max(0, number_value(thread_count, 0))
  pull.head_ref = text_value(first_value(pull.head_ref, pull.headRefName, pull.head and pull.head.ref), "")
  pull.base_ref = text_value(first_value(pull.base_ref, pull.baseRefName, pull.base and pull.base.ref), "")
  pull.head_sha = text_value(first_value(pull.head_sha, pull.headRefOid, pull.head and pull.head.sha), "")
  pull.review_decision = text_value(first_value(pull.review_decision, pull.reviewDecision), nil)
  if pull.is_draft == nil then
    pull.is_draft = boolean_value(first_value(pull.isDraft, pull.draft), false)
  end
  local state = text_value(pull.state, "open"):lower()
  pull.state = state == "open" and "Open" or state == "closed" and "Closed" or state == "merged" and "Merged" or pull.state
  pull.url = text_value(first_value(pull.url, pull.html_url), nil)
  local age_value = real_value(first_value(pull.created_at, pull.createdAt, pull.age))
  pull.age = age_value and util.relative_time(age_value, options) or ""
  local body = real_value(first_value(pull.body, pull.summary))
  if type(body) == "table" then
    local body_lines = {}
    for _, line in ipairs(body) do
      local value = text_value(line, nil)
      if value then
        table.insert(body_lines, value)
      end
    end
    pull.body = body_lines
  else
    pull.body = text_value(body, nil)
  end

  local reviews = {}
  for _, review in ipairs(connection_items(first_value(pull.reviews, pull.latestReviews))) do
    local normalized = normalize_review(review, options)
    if normalized and normalized.login ~= "" then
      table.insert(reviews, normalized)
    end
  end
  pull.reviews = reviews

  local reviewers = {}
  local reviewer_by_login = {}
  local requested_reviewers = {}
  for _, review in ipairs(reviews) do
    reviewer_by_login[review.login] = review
    table.insert(reviewers, review)
  end
  local requested_values = connection_items(first_value(
    pull.requested_reviewers,
    pull.requestedReviewers,
    pull.reviewRequests
  ))
  for _, requested in ipairs(requested_values) do
    local normalized = normalize_review(requested, options)
    if normalized and normalized.login ~= "" and not reviewer_by_login[normalized.login] then
      normalized.state = "pending"
      reviewer_by_login[normalized.login] = normalized
      table.insert(requested_reviewers, normalized)
      table.insert(reviewers, normalized)
    end
  end
  if #reviewers == 0 then
    for _, reviewer in ipairs(connection_items(pull.reviewers)) do
      local normalized = normalize_review(reviewer, options)
      if normalized and normalized.login ~= "" and not reviewer_by_login[normalized.login] then
        reviewer_by_login[normalized.login] = normalized
        table.insert(reviewers, normalized)
      end
    end
  end
  pull.reviewers = reviewers
  pull.requested_reviewers = requested_reviewers

  local comments = {}
  for _, comment in ipairs(connection_items(first_value(pull.comments, pull.issueComments, pull.issue_comments))) do
    local normalized = normalize_comment(comment, options, "comment")
    if normalized then
      table.insert(comments, normalized)
    end
  end
  local review_comments = {}
  for _, comment in ipairs(connection_items(first_value(pull.review_comments, pull.reviewComments))) do
    local normalized = normalize_comment(comment, options, "review_comment")
    if normalized then
      table.insert(review_comments, normalized)
      table.insert(comments, normalized)
    end
  end
  pull.review_comments = review_comments
  pull.comments = comments

  local commits = {}
  for _, commit in ipairs(list_value(pull.commits)) do
    if type(commit) == "table" then
      local commit_data = type(commit.commit) == "table" and commit.commit or {}
      local message = text_value(first_value(commit.messageHeadline, commit.message_headline), "")
      if message == "" then
        message = text_value(first_value(commit.message, commit.messageBody, commit_data.message), "")
      end
      message = message:match("^[^\r\n]+") or ""
      table.insert(commits, {
        sha = text_value(first_value(commit.sha, commit.oid), ""),
        message = message,
      })
    end
  end
  pull.commits = commits

  local files = {}
  local status_map = {
    ADDED = "A",
    MODIFIED = "M",
    DELETED = "D",
    RENAMED = "R",
    COPIED = "C",
    CHANGED = "M",
  }
  for _, file in ipairs(list_value(pull.files)) do
    if type(file) == "table" then
      local file_status = text_value(file.status, "M"):upper()
      table.insert(files, {
        path = text_value(first_value(file.path, file.filename), ""),
        status = status_map[file_status] or file_status or "M",
        additions = number_value(file.additions, 0),
        deletions = number_value(file.deletions, 0),
        threads = number_value(file.threads, 0),
        viewed = boolean_value(file.viewed, false),
      })
    end
  end
  pull.files = files
  pull.checks = M.normalize_checks(pull.statusCheckRollup or pull.checks)
  pull.statusCheckRollup = nil
  return pull
end

function M.normalize_threads(comments)
  comments = flatten_pages(comments)

  local threads = {}
  local by_location = {}
  for _, comment in ipairs(comments) do
    if type(comment) == "table" then
      local path = comment.path or comment.filename or ""
      local line = tonumber(comment.line or comment.original_line or comment.position) or 0
      local key = path .. ":" .. tostring(line)
      local thread = by_location[key]
      if not thread then
        thread = {
          id = #threads + 1,
          path = path,
          line = line,
          resolved = false,
          comments = {},
        }
        by_location[key] = thread
        table.insert(threads, thread)
      end
      table.insert(thread.comments, {
        author = comment.user and (comment.user.login or comment.user.name)
          or comment.author or "unknown",
        age = comment.created_at or comment.createdAt or "",
        body = comment.body or "",
      })
    end
  end
  return threads
end

function M.is_diff_too_large(value)
  return github_sdk.is_diff_too_large(value)
end

function M.build_patch_from_files(files)
  return github_sdk.build_patch_from_files(files)
end

local function run(command, options, callback)
  local completed = vim.system(command, options or { text = true }, function(result)
    local output = result.stdout or ""
    if result.code == 0 then
      schedule(callback, true, output)
    else
      schedule(callback, false, {
        code = result.code,
        message = util.trim(result.stderr ~= "" and result.stderr or result.stdout or "command failed"),
      })
    end
  end)
  return function()
    pcall(completed.kill, completed, 15)
  end
end

function M.github(options)
  options = options or {}
  local provider = {
    host = options.host,
    cwd = options.cwd or vim.fn.getcwd(),
    client = options.client or github_sdk.new({
      base_url = options.base_url,
      repository = options.repository,
      token = options.token,
      token_file = options.token_file,
      transport = options.transport,
      cwd = options.cwd or vim.fn.getcwd(),
      cache_items = options.cache_items,
      page_size = options.page_size,
    }),
  }

  function provider:list_pull_requests_page(query, page_options, callback)
    page_options = type(page_options) == "table" and page_options or {}
    local limit = page_options.limit or page_options.page_size or options.limit or 50
    local function handle_page(ok, result)
      if not ok then
        callback(ok, result)
        return
      end
      local pulls
      if type(result) == "table" and type(result.items) == "table" then
        pulls = result.items
      else
        pulls = type(result) == "table" and result or {}
      end
      for index, pull in ipairs(pulls) do
        pulls[index] = M.normalize_pull_request(pull)
      end
      callback(true, {
        pulls = pulls,
        total_count = math.max(tonumber(type(result) == "table" and result.total_count or nil) or #pulls, #pulls),
        has_next_page = type(result) == "table" and result.has_next_page == true,
        next_cursor = type(result) == "table" and result.next_cursor or nil,
      })
    end
    if self.client.list_pull_requests_page then
      return self.client:list_pull_requests_page(query, limit, page_options.after, handle_page)
    end
    return self.client:list_pull_requests(query, limit, handle_page)
  end

  function provider:list_pull_requests(query, callback)
    return self:list_pull_requests_page(query, { limit = options.limit or 50 }, function(ok, result)
      if not ok then
        callback(ok, result)
        return
      end
      callback(true, result.pulls)
    end)
  end

  function provider:get_pull_request_description(number, callback)
    if self.client.get_pull_request_description then
      return self.client:get_pull_request_description(number, callback)
    end
    if self.client.get_pull_request then
      return self.client:get_pull_request(number, function(ok, result)
        callback(ok, ok and text_value(result and result.body, "") or result)
      end)
    end
    callback(true, "")
  end

  function provider:get_pull_request(number, callback)
    return self.client:get_pull_request(number, function(ok, result)
      if not ok then
        callback(ok, result)
        return
      end
      callback(true, M.normalize_pull_request(result or {}))
    end)
  end

  function provider:get_patch(number, callback, pull)
    return self.client:get_pull_request_diff(number, function(ok, result)
      if ok or not M.is_diff_too_large(result) then
        callback(ok, result)
        return
      end
      return self.client:list_pull_request_files(number, function(files_ok, files_result)
        if not files_ok then
          callback(false, files_result)
          return
        end
        local files = type(files_result) == "table" and files_result or {}
        local patch = M.build_patch_from_files(files)
        if patch == "" then
          callback(false, {
            message = "could not find pull request diff: GitHub returned no file patches",
            pull = pull,
          })
          return
        end
        callback(true, patch)
      end)
    end)
  end

  function provider:list_threads(number, callback)
    return self.client:list_review_comments(number, function(ok, result)
      if not ok then
        callback(ok, result)
        return
      end
      local comments = result
      if type(comments) ~= "table" then
        callback(false, { message = "Unexpected GitHub review comment payload" })
        return
      end
      callback(true, M.normalize_threads(comments))
    end)
  end

  function provider:post_comment(number, body, callback)
    return self.client:post_issue_comment(number, body, callback)
  end

  function provider:submit_review(number, event, body, callback)
    return self.client:submit_pull_request_review(number, event, body, callback)
  end

  function provider:auth_status(callback)
    return self.client:get_authenticated_user(function(ok, result)
      if not ok then
        callback(false, result)
        return
      end
      callback(true, {
        authenticated = true,
        user = result.login or "",
        host = provider.host or "github.com",
      })
    end)
  end

  function provider:validate_access(callback)
    return self.client:get_repository(callback)
  end

  return provider
end

function M.git(options)
  options = options or {}
  local provider = {
    cwd = options.cwd or vim.fn.getcwd(),
  }

  function provider:compare(base, head, callback)
    local output = {}
    local commands = {
      { "git", "rev-list", "--left-right", "--count", ("%s...%s"):format(base, head) },
      { "git", "log", "--oneline", ("%s..%s"):format(base, head) },
      { "git", "diff", "--numstat", ("%s...%s"):format(base, head) },
    }
    local index = 1
    local function next_command()
      if index > #commands then
        callback(true, output)
        return
      end
      run(commands[index], { text = true, cwd = provider.cwd }, function(ok, result)
        if not ok then
          callback(ok, result)
          return
        end
        table.insert(output, result)
        index = index + 1
        next_command()
      end)
    end
    next_command()
  end

  return provider
end

function M.default(options)
  if options and options.kind == "git" then
    return M.git(options)
  end
  return M.github(options)
end

return M
