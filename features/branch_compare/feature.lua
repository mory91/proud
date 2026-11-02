-- Compare page: a sidebar (compare info, commits, files) next to the diff
-- pane. The head branch is checked out in place, so "All changes" shows
-- the real, editable files against the base (three-dot: from the merge
-- base; two-dot: from the base tip). Picking a commit shows that commit's
-- change against its parent instead. A pull request's diff is this page
-- for base...head, with the PR's review threads.
local git = require("proud.git")
local ui = require("proud.ui")
local keymap = require("proud.keymap")
local loader = require("proud.loader")
local section_row = require("proud.components.section_row")
local tree = require("proud.components.tree")

local M = {}

local function diff_view()
  return loader.load("diff_view")
end

local function sidebar()
  return loader.load("sidebar")
end

-- input: base, head (branch names), base_rev (git revision for the base,
-- default base), pull (a pull request: base/head come from it and the
-- branch is checked out from origin), threads, cwd, mode.
function M.create(input)
  input = input or {}
  local state = {
    base = input.base or "main",
    head = input.head or "feature",
    base_rev = input.base_rev,
    mode = input.mode or "three-dot",
    cwd = input.cwd,
    threads = vim.deepcopy(input.threads or {}),
    ahead = 0,
    behind = 0,
    commits = {},
    files = {},
    commit = nil,
    commit_files = {},
    loading = true,
  }
  if input.pull then
    M.set_pull(state, input.pull)
  end
  state.base_rev = state.base_rev or state.base
  state.diff = diff_view().create({
    cwd = state.cwd,
    threads = state.threads,
    title = M.title(state),
    message = M.loading_message(state),
  })
  state.sidebar = tree.create(M.sidebar_nodes(state), { selected_id = "commit:all" })
  return state
end

-- Applies pull request metadata: base/head come from the PR, and the base
-- is compared as origin/<base> (fetched with the checkout).
function M.set_pull(state, pull)
  pull = require("proud.provider").normalize_pull_request(pull)
  state.pull = pull
  if pull.head_ref and pull.head_ref ~= "" then
    state.base = pull.base_ref or "main"
    state.head = pull.head_ref
    state.base_rev = "origin/" .. state.base
  end
  if state.diff then
    state.diff.title = M.title(state)
  end
end

function M.title(state)
  local range = state.base .. (state.mode == "two-dot" and ".." or "...") .. state.head
  if state.pull then
    return "#" .. tostring(state.pull.number) .. " " .. range
  end
  return range
end

function M.loading_message(state)
  if state.pull and (state.pull.head_ref or "") == "" then
    return "Loading #" .. tostring(state.pull.number) .. "…"
  end
  return "Checking out " .. state.head .. "…"
end

-- Window bar label for "All changes": base...head.
function M.range_label(state)
  return {
    { state.base, "ProudAccentText" },
    { state.mode == "two-dot" and ".." or "...", "ProudMuted" },
    { state.head, "ProudSuccessText" },
  }
end

local function commit_label(commit)
  return {
    { commit.short or commit.sha:sub(1, 7), "ProudAccentText" },
    { "  " .. (commit.message or ""), "ProudBright" },
  }
end

local function totals(files)
  local additions, deletions = 0, 0
  for _, file in ipairs(files) do
    additions = additions + (file.additions or 0)
    deletions = deletions + (file.deletions or 0)
  end
  return additions, deletions
end

function M.swap(state)
  state.base, state.head = state.head, state.base
  state.base_rev = state.base
  state.ahead, state.behind = state.behind, state.ahead
end

function M.toggle_mode(state)
  state.mode = state.mode == "three-dot" and "two-dot" or "three-dot"
end

local function status_group(status)
  return status == "A" and "ProudSuccessText"
    or status == "D" and "ProudDangerText"
    or "ProudAccentText"
end

local function header(id, label, summary, children)
  return {
    id = id,
    kind = "header",
    label = label,
    expanded = true,
    spacing = 1,
    sections = {
      { text = label, group = "ProudBright" },
      { text = tostring(summary), group = "ProudMuted" },
    },
    children = children,
  }
end

local function placeholder(id, text)
  return {
    id = id,
    kind = "loading",
    marker = "",
    sections = { { text = text, group = "ProudMuted" } },
  }
end

local function info_row(id, sections)
  return { id = "info:" .. id, kind = "info", marker = "  ", spacing = 2, sections = sections }
end

local function thread_counts(state)
  local counts = {}
  for _, thread in ipairs(state.threads) do
    if not thread.resolved and thread.path then
      counts[thread.path] = (counts[thread.path] or 0) + 1
    end
  end
  return counts
end

-- Sidebar tree: Compare (info), Commits ("All changes" + each commit) and
-- the Files of the current selection.
function M.sidebar_nodes(state)
  local mode = state.mode == "two-dot" and "two-dot, from the base tip" or "three-dot, from merge base"
  local info = {
    info_row("base", {
      { text = "base", group = "ProudMuted" },
      { text = state.base, group = "ProudAccentText" },
      state.base_short and { text = "@ " .. state.base_short, group = "ProudMuted" } or nil,
    }),
    info_row("head", {
      { text = "head", group = "ProudMuted" },
      { text = state.head, group = "ProudSuccessText" },
      state.head_short and { text = "@ " .. state.head_short, group = "ProudMuted" } or nil,
    }),
    info_row("counts", {
      { text = "↑" .. state.ahead .. " ahead", group = "ProudSuccessText" },
      { text = "↓" .. state.behind .. " behind", group = "ProudWarning" },
      { text = state.pull and ("#" .. tostring(state.pull.number)) or "no PR yet", group = "ProudMuted" },
    }),
  }

  local commits = {}
  if state.loading then
    commits[1] = placeholder("loading:commits", "Loading commits…")
  else
    commits[1] = {
      id = "commit:all",
      kind = "commit",
      marker = state.commit == nil and "● " or "○ ",
      spacing = 1,
      sections = { { text = "All changes", group = state.commit == nil and "ProudBright" or "ProudMuted" } },
      payload = { all = true },
    }
    for _, commit in ipairs(state.commits) do
      local active = state.commit == commit.sha
      commits[#commits + 1] = {
        id = "commit:" .. commit.sha,
        kind = "commit",
        marker = active and "● " or "  ",
        spacing = 1,
        sections = {
          { text = commit.short or commit.sha:sub(1, 7), group = "ProudAccentText" },
          { text = commit.message or "", group = active and "ProudBright" or "ProudMuted" },
        },
        payload = { sha = commit.sha },
      }
    end
  end

  local files = state.commit and state.commit_files or state.files
  local threads = state.commit and {} or thread_counts(state)
  local file_nodes = {}
  if state.loading then
    file_nodes[1] = placeholder("loading:files", "Loading files…")
  end
  for _, file in ipairs(state.loading and {} or files) do
    local sections = {
      { text = file.status or "M", group = status_group(file.status) },
      { text = file.path, group = "ProudBright" },
      {
        parts = {
          { text = "+" .. tostring(file.additions or 0), group = "ProudSuccessText" },
          { text = " −" .. tostring(file.deletions or 0), group = "ProudDangerText" },
        },
      },
    }
    if threads[file.path] then
      sections[#sections + 1] = { text = "◆" .. threads[file.path], group = "ProudWarning" }
    end
    file_nodes[#file_nodes + 1] = {
      id = "file:" .. file.path,
      kind = "file",
      marker = "  ",
      spacing = 1,
      sections = sections,
      payload = { path = file.path, file = file },
    }
  end
  local additions, deletions = totals(files)
  local file_summary = state.loading and "" or ("%d  +%d −%d"):format(#files, additions, deletions)

  return {
    header("info", "Compare", mode, info),
    header("commits", "Commits", state.loading and "" or #state.commits, commits),
    header("files", "Files", file_summary, file_nodes),
  }
end

-- Rebuilds the sidebar tree, keeping selection and expansion.
local function rebuild_sidebar(state)
  local layout = tree.layout(state.sidebar)
  state.sidebar.roots = tree.create(M.sidebar_nodes(state)).roots
  tree.restore_layout(state.sidebar, layout)
  if not tree.selected(state.sidebar) then
    state.sidebar.selected_id = "commit:all"
  end
end

local function refresh(state)
  rebuild_sidebar(state)
  if state.refresh then
    state.refresh()
  end
end

-- Runs callbacks in parallel; done(ok, results | error) once all finish.
local function all(tasks, done)
  local results, pending, failed = {}, 0, false
  for _ in pairs(tasks) do
    pending = pending + 1
  end
  for name, task in pairs(tasks) do
    task(function(ok, value)
      if failed then
        return
      end
      if not ok then
        failed = true
        return done(false, value)
      end
      results[name] = value
      pending = pending - 1
      if pending == 0 then
        done(true, results)
      end
    end)
  end
end

local function fail(state, message)
  state.loading = false
  state.error = message
  diff_view().fail(state.diff, message)
  refresh(state)
end

-- Checks out the head (a pull request joins the background checkout the
-- overview started), then computes the base point, commits and files.
-- options: path (file to show first), commit (sha to select), on_ready.
function M.load(state, options)
  options = options or {}
  local cwd = state.cwd
  -- A newer load (swap, mode toggle) makes this one's callbacks stale.
  state.generation = (state.generation or 0) + 1
  local generation = state.generation
  local function stale()
    return state.generation ~= generation
  end
  state.loading = true
  state.error = nil
  diff_view().set_loading(state.diff, M.loading_message(state), M.range_label(state))
  refresh(state)

  local function checkout(callback)
    if state.pull then
      return git.prepare_pull(cwd, state.pull, function(ok, branch)
        if not ok then
          return callback(false, branch)
        end
        -- A no-op unless the branch was switched since the preparation.
        git.run(cwd, { "checkout", branch }, callback)
      end)
    end
    git.checkout_branch(cwd, state.head, callback)
  end

  checkout(function(ok, value)
    if stale() then
      return
    end
    if not ok then
      return fail(state, value)
    end
    local function base_point(callback)
      if state.mode == "two-dot" then
        return git.run(cwd, { "rev-parse", state.base_rev }, function(rev_ok, rev)
          callback(rev_ok, rev_ok and vim.trim(rev) or rev)
        end)
      end
      git.run(cwd, { "merge-base", state.base_rev, "HEAD" }, function(base_ok, base)
        callback(base_ok, base_ok and vim.trim(base) or base)
      end)
    end
    base_point(function(point_ok, point)
      if stale() then
        return
      end
      if not point_ok then
        return fail(state, point)
      end
      state.point = point
      all({
        base_short = function(done) git.short(cwd, state.base_rev, done) end,
        head_short = function(done) git.short(cwd, "HEAD", done) end,
        counts = function(done) git.ahead_behind(cwd, state.base_rev, "HEAD", done) end,
        commits = function(done) git.log(cwd, point .. "..HEAD", done) end,
        files = function(done) git.changed_files(cwd, point, done) end,
      }, function(all_ok, results)
        if stale() then
          return
        end
        if not all_ok then
          return fail(state, results)
        end
        state.base_short = results.base_short
        state.head_short = results.head_short
        state.ahead = results.counts.ahead
        state.behind = results.counts.behind
        state.commits = results.commits
        state.files = results.files
        state.loading = false
        M.select_commit(state, options.commit, options)
      end)
    end)
  end)
end

-- Shows "All changes" (sha nil: the working tree against the base point,
-- re-read so local edits count) or one commit against its parent.
function M.select_commit(state, sha, options)
  options = options or {}
  local cwd = state.cwd
  -- Only the latest selection is shown.
  state.selection = (state.selection or 0) + 1
  local selection = state.selection
  local generation = state.generation
  local function stale()
    return state.selection ~= selection or state.generation ~= generation
  end
  local commit
  for _, candidate in ipairs(state.commits) do
    if candidate.sha == sha or (sha and candidate.sha:sub(1, #sha) == sha) then
      commit = candidate
    end
  end
  local function shown(files, source, label)
    refresh(state)
    diff_view().set_files(state.diff, files, source, {
      label = label,
      path = options.path,
      on_ready = options.on_ready,
    })
  end
  if not commit then
    state.commit = nil
    state.commit_files = {}
    return git.changed_files(cwd, state.point, function(ok, files)
      if stale() then
        return
      end
      if not ok then
        return fail(state, files)
      end
      state.files = files
      shown(files, { kind = "worktree", base = state.point }, M.range_label(state))
    end)
  end
  state.commit = commit.sha
  git.parent(cwd, commit.sha, function(_, parent)
    git.changed_files(cwd, parent, function(ok, files)
      if stale() then
        return
      end
      if not ok then
        return fail(state, files)
      end
      state.commit_files = files
      shown(files, { kind = "commit", sha = commit.sha, short = commit.short, parent = parent }, commit_label(commit))
    end, commit.sha)
  end)
end

-- Replaces review threads (pull requests).
function M.set_threads(state, threads)
  state.threads = vim.deepcopy(threads or {})
  diff_view().set_threads(state.diff, state.threads)
  refresh(state)
end

-- Shows or hides the sidebar.
function M.toggle_sidebar(state)
  if state.workspace then
    ui.toggle_pane(state.workspace, "sidebar")
  end
end

local function sidebar_window(state)
  return ui.workspace_window(state.workspace, "sidebar")
end

function M.attach(state, options)
  options = options or {}
  local workspace = state.workspace
  local sidebar_buffer = ui.workspace_buffer(workspace, "sidebar")
  local function render()
    local window = sidebar_window(state)
    local width = window and vim.api.nvim_win_get_width(window) or 40
    ui.render_workspace(workspace, { sidebar = sidebar().render(state.sidebar, width) })
    sidebar().sync_cursor(state.sidebar, window)
  end
  state.refresh = render

  local function toggle()
    M.toggle_sidebar(state)
  end
  diff_view().attach(state.diff, ui.workspace_window(workspace, "diff"), {
    buffer = ui.workspace_buffer(workspace, "diff"),
    file_actions = { { "toggle_sidebar", toggle, "Show or hide the sidebar" } },
    on_file = function(_, file)
      if sidebar().select_file(state.sidebar, file.path) then
        sidebar().sync_cursor(state.sidebar, sidebar_window(state))
      end
    end,
  })

  sidebar().attach(sidebar_buffer, state.sidebar, {
    get_window = function()
      return sidebar_window(state)
    end,
    refresh = render,
    on_open = function(selected)
      for index, file in ipairs(state.diff.files) do
        if file.path == selected.path then
          diff_view().show_file(state.diff, index)
          ui.focus_workspace_pane(workspace, "diff")
        end
      end
    end,
    on_activate = function(node)
      if node.kind == "commit" and not state.loading then
        M.select_commit(state, node.payload.sha)
      end
    end,
  })
  keymap.map(sidebar_buffer, "n", "toggle_sidebar", toggle, "Show or hide the sidebar")
  if not state.pull then
    -- Ignored while loading: one checkout at a time in the repository.
    keymap.map(sidebar_buffer, "n", "swap_branches", function()
      if state.loading then
        return
      end
      M.swap(state)
      M.load(state)
    end, "Swap base and head")
  end
  keymap.map(sidebar_buffer, "n", "toggle_compare_mode", function()
    if state.loading then
      return
    end
    M.toggle_mode(state)
    state.diff.title = M.title(state)
    M.load(state)
  end, "Toggle compare mode")
  keymap.map(sidebar_buffer, "n", "open_pull_request", options.on_open_pr or function() end, "Open pull request")
  local close = options.on_quit or function()
    ui.close_workspace(workspace)
  end
  keymap.bind_common_buffer(sidebar_buffer, { on_quit = close })
  keymap.bind_common_buffer(state.diff.scene.status_buffer, { on_quit = close })
  render()
end

-- Opens the page in a new tab: sidebar | diff. options: load (false to
-- call M.load later, e.g. while PR metadata loads), path, commit,
-- on_ready, on_quit, on_open_pr.
function M.open(state, options)
  options = options or {}
  local name = state.pull and ("proud://pr/" .. tostring(state.pull.number) .. "/compare")
    or ("proud://compare/" .. state.base .. "..." .. state.head)
  local title = state.pull and ("#" .. tostring(state.pull.number) .. " compare")
    or ("compare  " .. state.base .. "..." .. state.head)
  local workspace = ui.open_workspace(name, {
    {
      name = "sidebar",
      buffer_name = name .. "/sidebar",
      title = title,
      view = sidebar().render(state.sidebar, 40),
      weight = 0.28,
    },
    {
      name = "diff",
      buffer_name = name .. "/diff",
      title = title,
      external = true,
      weight = 0.72,
    },
  }, {
    focus = "sidebar",
    title = title,
    statusline = title,
    on_resize = function()
      if state.refresh then
        state.refresh()
      end
    end,
    on_close = function()
      diff_view().detach(state.diff)
    end,
    on_closed = function()
      diff_view().unload(state.diff)
    end,
  })
  state.workspace = workspace
  state.close = workspace.close
  M.attach(state, options)
  if options.load ~= false then
    M.load(state, options)
  end
  return ui.workspace_buffer(workspace, "sidebar")
end

return M
