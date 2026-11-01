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
local function checkout_branch(cwd, branch, start, callback)
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
      checkout_branch(cwd, branch, "FETCH_HEAD", function(checked_out, result)
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
function M.merge_base(cwd, base_ref, callback)
  sequence({
    function(next)
      M.run(cwd, { "fetch", "origin", base_ref }, next)
    end,
    function(next)
      M.run(cwd, { "merge-base", "origin/" .. base_ref, "HEAD" }, next)
    end,
  }, function(ok, value)
    callback(ok, ok and vim.trim(value) or value)
  end)
end

-- Files changed between `base` and the working tree (local edits included).
-- callback(ok, { { status = "M"|"A"|"D"|"R", path = ..., old_path = ... } })
function M.changed_files(cwd, base, callback)
  M.run(cwd, { "diff", "--name-status", "-M", "--no-color", base }, function(ok, value)
    if not ok then
      return callback(false, value)
    end
    local files = {}
    for line in value:gmatch("[^\n]+") do
      local fields = vim.split(line, "\t", { plain = true })
      local status = fields[1]:sub(1, 1)
      if status == "R" or status == "C" then
        files[#files + 1] = { status = status, old_path = fields[2], path = fields[3] }
      else
        files[#files + 1] = { status = status, path = fields[2], old_path = fields[2] }
      end
    end
    callback(true, files)
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

function M.toplevel(cwd, callback)
  M.run(cwd, { "rev-parse", "--show-toplevel" }, function(ok, value)
    callback(ok, ok and vim.trim(value) or value)
  end)
end

return M
