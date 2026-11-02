-- Asynchronous git operations through the git command line (vim.system).
-- Every callback receives (ok, value_or_error). On failure the error is
-- the command that failed and git's own message, meant to be shown to the
-- user unchanged.
local M = {}

local function describe(args, result)
  local message = vim.trim((result.stderr or "") ~= "" and result.stderr or (result.stdout or ""))
  if message == "" then
    message = ("exited with code %d"):format(result.code or -1)
  end
  return ("git %s\n%s"):format(table.concat(args, " "), message)
end

-- Runs `git -C cwd <args>`; callback(ok, stdout | error) on the main loop.
function M.run(cwd, args, callback)
  local command = { "git", "-C", cwd }
  vim.list_extend(command, args)
  local ok, err = pcall(vim.system, command, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        callback(true, result.stdout or "")
      else
        callback(false, describe(args, result))
      end
    end)
  end)
  if not ok then
    vim.schedule(function()
      callback(false, ("git %s\n%s"):format(table.concat(args, " "), tostring(err)))
    end)
  end
end

-- Runs steps in order, stopping at the first failure. Each step is
-- function(next) where next(ok, value) continues or stops.
local function sequence(steps, callback)
  local index = 0
  local function step(ok, value)
    if not ok then
      return callback(false, value)
    end
    index = index + 1
    if index > #steps then
      return callback(true, value)
    end
    steps[index](step)
  end
  step(true)
end

local function branch_exists(cwd, branch, callback)
  M.run(cwd, { "rev-parse", "--verify", "--quiet", "refs/heads/" .. branch }, function(ok)
    callback(ok)
  end)
end

-- Checks out `branch`, creating it from `start` when it does not exist yet.
local function checkout_or_create(cwd, branch, start, callback)
  branch_exists(cwd, branch, function(exists)
    if exists then
      M.run(cwd, { "checkout", branch }, callback)
    else
      M.run(cwd, { "checkout", "-b", branch, start }, callback)
    end
  end)
end

-- Fetches and checks out a pull request's head in place:
--   1. origin/<head_ref> as the local branch <head_ref> (tracking origin)
--   2. otherwise (e.g. a fork) pull/<number>/head as the local branch pr-<number>
-- callback(ok, branch | error). Git errors are passed through unchanged.
function M.checkout_pull(cwd, pull, callback)
  local head_ref = pull.head_ref
  local function from_pull_ref(previous_error)
    local branch = "pr-" .. tostring(pull.number)
    M.run(cwd, { "fetch", "origin", ("pull/%s/head"):format(tostring(pull.number)) }, function(ok, value)
      if not ok then
        return callback(false, previous_error and (previous_error .. "\n\n" .. value) or value)
      end
      checkout_or_create(cwd, branch, "FETCH_HEAD", function(checked_out, result)
        callback(checked_out, checked_out and branch or result)
      end)
    end)
  end
  if not head_ref or head_ref == "" then
    return from_pull_ref(nil)
  end
  M.run(cwd, { "fetch", "origin", head_ref }, function(ok, value)
    if not ok then
      return from_pull_ref(value)
    end
    branch_exists(cwd, head_ref, function(exists)
      local args = exists and { "checkout", head_ref } or { "checkout", "-b", head_ref, "--track", "origin/" .. head_ref }
      M.run(cwd, args, function(checked_out, result)
        callback(checked_out, checked_out and head_ref or result)
      end)
    end)
  end)
end

-- Fetches the base branch and returns the merge base of origin/<base_ref>
-- and HEAD, which is what a pull request's diff is computed against.
-- options.fetch = false skips the fetch (already done by prepare_pull).
function M.merge_base(cwd, base_ref, callback, options)
  local fetch = not (options and options.fetch == false)
  sequence({
    function(next)
      if not fetch then
        return next(true)
      end
      M.run(cwd, { "fetch", "origin", base_ref }, next)
    end,
    function(next)
      M.run(cwd, { "merge-base", "origin/" .. base_ref, "HEAD" }, next)
    end,
  }, function(ok, value)
    callback(ok, ok and vim.trim(value) or value)
  end)
end

-- Parses `git diff -z --name-status` / `--numstat` output into files.
local function parse_changes(name_status, numstat)
  local files, by_path = {}, {}
  local fields = vim.split(name_status, "\0", { plain = true })
  local index = 1
  while index <= #fields do
    local code = fields[index]
    if code == "" then
      break
    end
    local status = code:sub(1, 1)
    local file
    if status == "R" or status == "C" then
      file = { status = status, old_path = fields[index + 1], path = fields[index + 2] }
      index = index + 3
    else
      file = { status = status, path = fields[index + 1], old_path = fields[index + 1] }
      index = index + 2
    end
    file.additions, file.deletions = 0, 0
    files[#files + 1] = file
    by_path[file.path] = file
  end
  -- numstat -z: "added\tdeleted\tpath\0", or for renames
  -- "added\tdeleted\t\0old\0new\0". Binary files report "-".
  fields = vim.split(numstat or "", "\0", { plain = true })
  index = 1
  while index <= #fields do
    local added, deleted, path = fields[index]:match("^([%d-]+)\t([%d-]+)\t(.*)$")
    if not added then
      break
    end
    if path == "" then
      path = fields[index + 2]
      index = index + 3
    else
      index = index + 1
    end
    local file = by_path[path]
    if file then
      file.additions = tonumber(added) or 0
      file.deletions = tonumber(deleted) or 0
      file.binary = added == "-"
    end
  end
  return files
end

-- Files changed from `base` to `head`, or to the working tree when `head`
-- is nil (local edits included), with line counts.
-- callback(ok, { { status = "M"|"A"|"D"|"R", path, old_path, additions, deletions } })
function M.changed_files(cwd, base, callback, head)
  local range = { base, head }
  local name_status = { "diff", "-z", "--name-status", "-M", "--no-color" }
  local numstat = { "diff", "-z", "--numstat", "-M", "--no-color" }
  vim.list_extend(name_status, range)
  vim.list_extend(numstat, range)
  M.run(cwd, name_status, function(ok, names)
    if not ok then
      return callback(false, names)
    end
    M.run(cwd, numstat, function(counted, counts)
      if not counted then
        return callback(false, counts)
      end
      callback(true, parse_changes(names, counts))
    end)
  end)
end

-- Git's empty tree: the "parent" of a root commit.
M.EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

-- The first parent of `rev`, or the empty tree for a root commit.
function M.parent(cwd, rev, callback)
  M.run(cwd, { "rev-parse", "--verify", "--quiet", rev .. "^" }, function(ok, value)
    callback(true, ok and vim.trim(value) or M.EMPTY_TREE)
  end)
end

-- Commits in `range` (e.g. "<merge-base>..HEAD"), newest first.
-- callback(ok, { { sha, short, message } })
function M.log(cwd, range, callback)
  M.run(cwd, { "log", "--no-color", "--format=%H%x09%h%x09%s", range }, function(ok, value)
    if not ok then
      return callback(false, value)
    end
    local commits = {}
    for line in value:gmatch("[^\n]+") do
      local sha, short, message = line:match("^(%x+)\t(%x+)\t(.*)$")
      if sha then
        commits[#commits + 1] = { sha = sha, short = short, message = message }
      end
    end
    callback(true, commits)
  end)
end

-- Commits only in `head` (ahead) and only in `base` (behind).
function M.ahead_behind(cwd, base, head, callback)
  M.run(cwd, { "rev-list", "--left-right", "--count", base .. "..." .. head }, function(ok, value)
    if not ok then
      return callback(false, value)
    end
    local behind, ahead = value:match("(%d+)%s+(%d+)")
    callback(true, { ahead = tonumber(ahead) or 0, behind = tonumber(behind) or 0 })
  end)
end

-- Abbreviated object name of `rev`.
function M.short(cwd, rev, callback)
  M.run(cwd, { "rev-parse", "--short", rev }, function(ok, value)
    callback(ok, ok and vim.trim(value) or value)
  end)
end

-- Checks out a local branch in place; when only origin/<branch> exists,
-- creates the local branch tracking it. callback(ok, branch | error).
function M.checkout_branch(cwd, branch, callback)
  branch_exists(cwd, branch, function(exists)
    if exists then
      return M.run(cwd, { "checkout", branch }, function(ok, value)
        callback(ok, ok and branch or value)
      end)
    end
    M.run(cwd, { "rev-parse", "--verify", "--quiet", "refs/remotes/origin/" .. branch }, function(remote)
      local args = remote and { "checkout", "-b", branch, "--track", "origin/" .. branch } or { "checkout", branch }
      M.run(cwd, args, function(ok, value)
        callback(ok, ok and branch or value)
      end)
    end)
  end)
end

-- Content of `path` at `rev`, or "" when the file does not exist there
-- (an added file).
function M.show(cwd, rev, path, callback)
  M.run(cwd, { "show", rev .. ":" .. path }, function(ok, value)
    if ok then
      callback(true, value)
    elseif value:find("does not exist", 1, true) or value:find("exists on disk, but not in", 1, true) then
      callback(true, "")
    else
      callback(false, value)
    end
  end)
end

-- Background preparation of a pull request: checkout_pull, then fetch the
-- base branch. Jobs are shared per repository and pull request, so the
-- overview can start one and the diff can join it (or take its finished
-- result) instead of starting over:
--   prepare_pull(cwd, pull)            starts the job (no-op if one exists)
--   prepare_pull(cwd, pull, callback)  starts or joins; callback(ok, branch | error)
-- A finished success is handed to the first caller with a callback and
-- then forgotten, so the next overview fetches again. A failure is never
-- kept: the next caller retries against the repository as it is then.
local jobs = {}

local function job_key(cwd, pull)
  return table.concat({ cwd, tostring(pull.number), pull.head_ref or "", pull.base_ref or "" }, "\0")
end

function M.prepare_pull(cwd, pull, callback)
  local key = job_key(cwd, pull)
  local job = jobs[key]
  if job and job.done then
    if callback then
      jobs[key] = nil
      vim.schedule(function()
        callback(true, job.branch)
      end)
    end
    return
  end
  if job then
    if callback then
      job.waiting[#job.waiting + 1] = callback
    end
    return
  end
  job = { waiting = { callback } }
  jobs[key] = job
  local function finish(ok, value)
    local waiting = job.waiting
    job.waiting = {}
    if ok and #waiting == 0 then
      job.done, job.branch = true, value
    elseif jobs[key] == job then
      jobs[key] = nil
    end
    for _, waiter in ipairs(waiting) do
      waiter(ok, value)
    end
  end
  M.checkout_pull(cwd, pull, function(ok, branch)
    if not ok then
      return finish(false, branch)
    end
    M.run(cwd, { "fetch", "origin", pull.base_ref or "main" }, function(fetched, value)
      finish(fetched, fetched and branch or value)
    end)
  end)
end

-- State of the background preparation for this pull request: "running",
-- "ready" (finished, unclaimed) or nil.
function M.preparation(cwd, pull)
  local job = jobs[job_key(cwd, pull)]
  return job and (job.done and "ready" or "running") or nil
end

function M.toplevel(cwd, callback)
  M.run(cwd, { "rev-parse", "--show-toplevel" }, function(ok, value)
    callback(ok, ok and vim.trim(value) or value)
  end)
end

return M
