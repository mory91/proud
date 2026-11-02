-- Builds a real temporary git repository from proud.fixtures for the demo,
-- tests and benchmarks: a working clone on the base branch, plus a local
-- bare "origin" with the PR's head branch and refs/pull/<n>/head.
local diff = require("proud.diff")
local fixtures = require("proud.fixtures")

local M = {}

local function git(cwd, args)
  local command = { "git", "-C", cwd }
  vim.list_extend(command, args)
  local result = vim.system(command, { text = true }):wait()
  if result.code ~= 0 then
    error(("fixture repo: git %s failed: %s"):format(table.concat(args, " "), result.stderr or ""))
  end
  return vim.trim(result.stdout or "")
end

local function write(root, path, lines)
  local full = root .. "/" .. path
  vim.fn.mkdir(vim.fn.fnamemodify(full, ":h"), "p")
  vim.fn.writefile(lines, full)
end

local function source_lines(source)
  if type(source) == "string" then
    return vim.split((source:gsub("\n$", "")), "\n", { plain = true })
  end
  return source or {}
end

-- Base and head contents of every fixture file: head is the fixture
-- source; base drops added rows and restores deleted ones.
function M.contents()
  local files = {}
  for _, file in ipairs(diff.parse_patch(fixtures.patch)) do
    local head = source_lines(fixtures.file_sources[file.path])
    local base = {}
    for _, row in ipairs(diff.file_rows(file, head)) do
      if row.kind == "context" or row.kind == "delete" then
        base[#base + 1] = row.text
      end
    end
    if vim.deep_equal(base, head) then
      -- The patch's line numbers do not match the fixture source (e.g. a
      -- hunk at line 20 of an 8-line file): derive the base by text,
      -- dropping the patch's added lines and keeping its deleted ones.
      local added, deleted = {}, {}
      for _, line in ipairs(file.lines or {}) do
        if line.kind == "add" then
          added[line.text] = (added[line.text] or 0) + 1
        elseif line.kind == "delete" then
          deleted[#deleted + 1] = line.text
        end
      end
      base = {}
      for _, text in ipairs(head) do
        if (added[text] or 0) > 0 then
          added[text] = added[text] - 1
        else
          base[#base + 1] = text
        end
      end
      vim.list_extend(base, deleted)
    end
    files[#files + 1] = { path = file.path, base = base, head = head }
  end
  return files
end

-- Commit message for each changed file's commit on the PR branch.
M.messages = {
  ["packages/runner/src/config.ts"] = "Read retry limits from config",
  ["packages/runner/src/task/retry.ts"] = "Add exponential backoff",
}

-- Creates the repository; returns { root, work, origin, number, base_ref,
-- head_ref, head_sha }. `options.files` overrides M.contents(), and
-- `options.messages` the commit messages (by path).
function M.create(options)
  options = options or {}
  local pull = fixtures.overview
  local root = vim.fn.tempname()
  local work = root .. "/work"
  local origin = root .. "/origin.git"
  vim.fn.mkdir(work, "p")
  local base_ref = options.base_ref or pull.base_ref or "main"
  local head_ref = options.head_ref or pull.head_ref or "feature"
  local number = options.number or pull.number or 1
  local files = options.files or M.contents()

  git(work, { "init", "-q", "-b", base_ref })
  git(work, { "config", "user.email", "fixture@proud.test" })
  git(work, { "config", "user.name", "Proud Fixture" })
  git(work, { "config", "commit.gpgsign", "false" })
  for _, file in ipairs(files) do
    if #file.base > 0 then
      write(work, file.path, file.base)
    end
  end
  write(work, "README.md", { "fixture" })
  git(work, { "add", "-A" })
  git(work, { "commit", "-q", "-m", "base" })

  -- One commit per changed file, so the branch has commits to pick from.
  git(work, { "checkout", "-q", "-b", head_ref })
  for _, file in ipairs(files) do
    if #file.head > 0 then
      write(work, file.path, file.head)
    else
      git(work, { "rm", "-q", file.path })
    end
    git(work, { "add", "-A" })
    git(work, { "commit", "-q", "-m", (options.messages or M.messages)[file.path] or ("Update " .. file.path) })
  end
  local head_sha = git(work, { "rev-parse", "HEAD" })

  git(root, { "clone", "-q", "--bare", work, origin })
  git(origin, { "update-ref", ("refs/pull/%d/head"):format(number), head_sha })
  git(work, { "remote", "add", "origin", origin })
  git(work, { "fetch", "-q", "origin" })
  git(work, { "checkout", "-q", base_ref })
  git(work, { "branch", "-q", "-D", head_ref })

  return {
    root = root,
    work = work,
    origin = origin,
    number = number,
    base_ref = base_ref,
    head_ref = head_ref,
    head_sha = head_sha,
  }
end

function M.remove(repo)
  if repo and repo.root then
    vim.fn.delete(repo.root, "rf")
  end
end

return M
