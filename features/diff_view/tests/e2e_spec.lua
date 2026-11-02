return function(test)
  local feature = require("proud.loader").load("diff_view")
  local fixtures = require("proud.fixtures")
  local fixture_repo = require("proud.fixture_repo")
  local git = require("proud.git")
  local inline = require("proud.ui.inline_diff")

  local function plain(bar)
    return (bar or ""):gsub("%%#[%w_]+#", "")
  end
  local function git_out(repo, args)
    local command = { "git", "-C", repo.work }
    vim.list_extend(command, args)
    return vim.trim(vim.system(command, { text = true }):wait().stdout or "")
  end
  local function await(start)
    local done, value
    start(function(ok, result)
      done, value = ok, result
    end)
    vim.wait(10000, function() return done ~= nil end, 10)
    return value
  end

  -- The pane in a plain window, on the checked-out PR branch.
  local repo = fixture_repo.create()
  git_out(repo, { "checkout", "-q", "-b", repo.head_ref, "origin/" .. repo.head_ref })
  local base = git_out(repo, { "merge-base", "origin/main", "HEAD" })
  vim.cmd("tabnew")
  local tabpage = vim.api.nvim_get_current_tabpage()
  local window = vim.api.nvim_get_current_win()
  local toggled = 0
  local shown = {}
  local state = feature.create({ cwd = repo.work, threads = fixtures.threads, title = "#482" })
  local status_buffer = feature.attach(state, window, {
    file_actions = { { "toggle_sidebar", function() toggled = toggled + 1 end, "Toggle" } },
    on_file = function(index) shown[#shown + 1] = index end,
  })
  test.eq(status_buffer, vim.api.nvim_win_get_buf(window), "the pane starts on its status buffer")
  test.truthy(vim.wo[window].number, "Neovim's own line numbers are used")

  local files = await(function(done) git.changed_files(repo.work, base, done) end)
  test.eq(2, #files, "two files changed on the branch")
  test.eq(5, files[1].additions, "changed files carry line counts")
  local ready
  feature.set_files(state, files, { kind = "worktree", base = base }, {
    label = { { "main", "ProudAccentText" }, { "...", "ProudMuted" }, { repo.head_ref, "ProudSuccessText" } },
    on_ready = function(buffer) ready = buffer end,
  })
  test.truthy(vim.wait(5000, function() return ready ~= nil end, 10), "the first file opens")
  local buffer = ready
  test.eq(
    vim.uv.fs_realpath(repo.work .. "/packages/runner/src/config.ts"),
    vim.uv.fs_realpath(vim.api.nvim_buf_get_name(buffer)),
    "the real file is opened"
  )
  test.eq("", vim.bo[buffer].buftype, "the file is a normal buffer")
  test.truthy(vim.bo[buffer].modifiable, "the file is editable")
  test.contains(plain(vim.wo[window].winbar), "main...feat/task-retry-backoff   packages/runner/src/config.ts   [+5 −0]   1 / 2", "the window bar shows label, file, counts and position")
  test.eq({ 1 }, shown, "the host hears which file is shown")
  local added = 0
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, inline.namespace, 0, -1, { details = true })) do
    if mark[4].line_hl_group == "ProudAddLine" then
      added = added + 1
    end
  end
  test.eq(5, added, "added lines are highlighted")
  local thread_marks = vim.api.nvim_buf_get_extmarks(buffer, feature.thread_namespace, 0, -1, { details = true })
  test.eq(1, #thread_marks, "the file's thread is marked")
  test.eq(5, thread_marks[1][2], "the thread sits on its line")
  test.contains(thread_marks[1][4].virt_text[1][1], "◆ dev-lee: Can maxDelayMs", "open threads preview their first comment")

  vim.api.nvim_buf_set_lines(buffer, 0, 0, false, { "// local edit" })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buffer })
  test.truthy(vim.wait(2000, function() return plain(vim.wo[window].winbar):find("[+6 −0]", 1, true) ~= nil end, 10), "editing updates the diff live")
  local moved = vim.api.nvim_buf_get_extmark_by_id(buffer, feature.thread_namespace, thread_marks[1][1], {})
  test.eq(6, moved[1], "thread marks move with edits")

  vim.api.nvim_set_current_win(window)
  vim.api.nvim_feedkeys("]f", "x", false)
  test.truthy(vim.wait(5000, function() return state.file_cursor == 2 and vim.api.nvim_win_get_buf(window) ~= buffer end, 20), "]f opens the next file")
  test.contains(plain(vim.wo[window].winbar), "task/retry.ts   [+6 −2]   2 / 2", "the window bar follows the file")
  test.truthy(vim.bo[buffer].modified, "the previous file keeps its unsaved edit")
  test.eq(0, #vim.tbl_filter(function(map) return map.lhs == "]f" end, vim.api.nvim_buf_get_keymap(buffer, "n")), "the previous file's mappings are removed")
  local deleted = 0
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(window), inline.namespace, 0, -1, { details = true })) do
    deleted = deleted + #(mark[4].virt_lines or {})
  end
  test.eq(2, deleted, "deleted lines are shown as virtual lines")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<leader>e", true, false, true), "x", false)
  test.eq(1, toggled, "host actions are mapped on shown files")

  state.thread_cursor = 2
  vim.api.nvim_feedkeys("]t", "x", false)
  test.truthy(vim.wait(5000, function() return state.file_cursor == 2 and vim.api.nvim_win_get_cursor(window)[1] == 14 end, 20), "]t jumps to the thread's line")
  local retry_buffer = vim.api.nvim_win_get_buf(window)

  -- One commit against its parent: a read-only snapshot, no threads.
  local commits = await(function(done) git.log(repo.work, base .. "..HEAD", done) end)
  test.eq(2, #commits, "the branch has two commits")
  local commit = commits[2]
  test.eq("Add exponential backoff", commit.message, "commits are listed newest first")
  local parent = await(function(done) git.parent(repo.work, commit.sha, done) end)
  local commit_files = await(function(done) git.changed_files(repo.work, parent, done, commit.sha) end)
  test.eq(1, #commit_files, "the commit changed one file")
  test.eq("packages/runner/src/task/retry.ts", commit_files[1].path, "the commit's own file")
  ready = nil
  feature.set_files(state, commit_files, { kind = "commit", sha = commit.sha, short = commit.short, parent = parent }, {
    label = { { commit.short, "ProudAccentText" } },
    on_ready = function(shown_buffer) ready = shown_buffer end,
  })
  test.truthy(vim.wait(5000, function() return ready ~= nil end, 10), "the commit's file opens")
  test.contains(vim.api.nvim_buf_get_name(ready), "proud://commit/" .. commit.short, "the commit's version is a snapshot")
  test.truthy(not vim.bo[ready].modifiable, "a commit's version is read-only")
  test.eq("typescript", vim.bo[ready].filetype, "snapshots get the file's syntax")
  test.contains(plain(vim.wo[window].winbar), commit.short .. "   packages/runner/src/task/retry.ts   [+6 −2]   1 / 1", "the window bar shows the commit's change")
  test.eq(0, #vim.api.nvim_buf_get_extmarks(ready, feature.thread_namespace, 0, -1, {}), "threads are not placed on commits")
  local current_buffer, current_handle = feature.current(state)
  test.eq(ready, current_buffer, "current() reports the shown buffer")
  test.truthy(current_handle ~= nil, "current() reports its diff")

  -- Cleanup, as a host does on close.
  feature.detach(state)
  vim.cmd("tabclose")
  feature.unload(state)
  test.truthy(not vim.api.nvim_tabpage_is_valid(tabpage), "the host tab is gone")
  test.truthy(not vim.api.nvim_buf_is_valid(ready), "commit snapshots are deleted")
  test.truthy(not vim.api.nvim_buf_is_valid(retry_buffer), "unmodified files the pane opened are unloaded")
  test.truthy(vim.api.nvim_buf_is_valid(buffer) and vim.bo[buffer].modified, "files with unsaved edits stay")
  test.eq(0, #vim.api.nvim_buf_get_extmarks(buffer, inline.namespace, 0, -1, {}), "kept files lose their diff decorations")
  test.eq(0, #vim.api.nvim_buf_get_extmarks(buffer, feature.thread_namespace, 0, -1, {}), "kept files lose their thread marks")
  test.eq(0, #vim.tbl_filter(function(map) return map.lhs == "]t" or map.lhs == "]f" end, vim.api.nvim_buf_get_keymap(buffer, "n")), "kept files lose their mappings")
  pcall(vim.api.nvim_buf_delete, buffer, { force = true })
  fixture_repo.remove(repo)

  -- Background checkout jobs: callers share one job; a finished result is
  -- claimed once; failures are not kept.
  local shared = fixture_repo.create()
  local run = git.run
  local fetches = 0
  git.run = function(cwd, args, callback)
    if args[1] == "fetch" then
      fetches = fetches + 1
    end
    return run(cwd, args, callback)
  end
  local results = {}
  git.prepare_pull(shared.work, fixtures.overview)
  git.prepare_pull(shared.work, fixtures.overview, function(ok, value) results[#results + 1] = { ok, value } end)
  git.prepare_pull(shared.work, fixtures.overview, function(ok, value) results[#results + 1] = { ok, value } end)
  test.truthy(vim.wait(15000, function() return #results == 2 end, 20), "joined callers are answered")
  test.eq(2, fetches, "one job runs for all callers (head and base fetch)")
  test.eq({ true, "feat/task-retry-backoff" }, results[1], "callers get the checked-out branch")
  test.eq(nil, git.preparation(shared.work, fixtures.overview), "a claimed job is forgotten")
  git.prepare_pull(shared.work, fixtures.overview)
  test.truthy(vim.wait(15000, function() return git.preparation(shared.work, fixtures.overview) == "ready" end, 20), "an unclaimed finished job is kept")
  test.eq(4, fetches, "a new preparation fetches again")
  local claimed
  git.prepare_pull(shared.work, fixtures.overview, function(ok) claimed = ok end)
  test.truthy(vim.wait(1000, function() return claimed ~= nil end, 10), "a finished job answers at once")
  test.eq(4, fetches, "claiming a finished job does not fetch")
  git.run = run
  fixture_repo.remove(shared)

  local conflicted = fixture_repo.create()
  vim.fn.writefile({ "local uncommitted change" }, conflicted.work .. "/packages/runner/src/config.ts")
  git.prepare_pull(conflicted.work, fixtures.overview)
  test.truthy(vim.wait(15000, function() return git.preparation(conflicted.work, fixtures.overview) == nil end, 20), "a failed background checkout is not kept")
  fixture_repo.remove(conflicted)
end
