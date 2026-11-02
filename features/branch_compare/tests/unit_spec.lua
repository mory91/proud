return function(test)
  local feature = require("proud.loader").load("branch_compare")
  local sidebar = require("proud.loader").load("sidebar")
  local tree = require("proud.components.tree")
  local fixtures = require("proud.fixtures")

  local function render(state)
    return sidebar.render(tree.create(feature.sidebar_nodes(state)), 60)
  end
  local function text(view)
    return table.concat(view.lines, "\n")
  end

  -- Before git data: info rows and loading placeholders.
  local state = feature.create({ base = "main", head = "feat/monitor-diffs", cwd = "/tmp/repo" })
  test.eq("main", state.base_rev, "a plain compare uses the base branch as given")
  test.eq("main...feat/monitor-diffs", feature.title(state), "three-dot is the default")
  test.contains(feature.loading_message(state), "Checking out feat/monitor-diffs", "loading names the branch being checked out")
  local loading = render(state)
  test.contains(text(loading), "Compare three-dot, from merge base", "the info section names the mode")
  test.contains(text(loading), "Loading commits", "commits load in place")
  test.contains(text(loading), "Loading files", "files load in place")
  test.contains(text(loading), "no PR yet", "a plain compare has no pull request")

  -- After git data: All changes, commits and files.
  state.loading = false
  state.base_short, state.head_short = "4c0e1aa", "9a7d3f0"
  state.ahead, state.behind = 12, 3
  state.commits = {
    { sha = "9a7d3f0aaaa", short = "9a7d3f0", message = "Track removed rows" },
    { sha = "52e81bcbbbb", short = "52e81bc", message = "Index snapshot rows by key" },
  }
  state.files = {
    { status = "M", path = "monitor/src/diff.ts", additions = 22, deletions = 4 },
    { status = "A", path = "monitor/src/rowKey.ts", additions = 30, deletions = 0 },
  }
  local ready = render(state)
  test.contains(text(ready), "base  main  @ 4c0e1aa", "the base is shown with its commit")
  test.contains(text(ready), "head  feat/monitor-diffs  @ 9a7d3f0", "the head is shown with its commit")
  test.highlighted(ready, "↑12 ahead", "ProudSuccessText", "ahead is green")
  test.highlighted(ready, "↓3 behind", "ProudWarning", "behind warns")
  test.contains(text(ready), "Commits 2", "commits are counted")
  test.contains(text(ready), "● All changes", "All changes is selected by default")
  test.highlighted(ready, "9a7d3f0", "ProudAccentText", "commit ids are accented")
  test.contains(text(ready), "Files 2  +52 −4", "files are counted with totals")
  test.highlighted(ready, "+22", "ProudSuccessText", "additions are green")
  test.highlighted(ready, " −4", "ProudDangerText", "deletions are red")

  -- A selected commit shows its own files.
  state.commit = "52e81bcbbbb"
  state.commit_files = { { status = "M", path = "monitor/src/diff.ts", additions = 3, deletions = 1 } }
  local committed = render(state)
  test.contains(text(committed), "○ All changes", "All changes is no longer selected")
  test.contains(text(committed), "● 52e81bc", "the selected commit is marked")
  test.contains(text(committed), "Files 1  +3 −1", "the files are the commit's")

  -- Swapping and modes.
  feature.swap(state)
  test.eq("feat/monitor-diffs", state.base)
  test.eq("feat/monitor-diffs", state.base_rev, "swapping compares against the new base")
  test.eq(3, state.ahead, "swapping reverses ahead and behind")
  feature.toggle_mode(state)
  test.eq("two-dot", state.mode)
  test.eq("feat/monitor-diffs..main", feature.title(state), "two-dot uses ..")
  test.contains(text(render(state)), "two-dot, from the base tip", "the info section follows the mode")
  test.eq("..", feature.range_label(state)[2][1], "the window bar label follows the mode")

  -- A pull request: base/head from the PR, base compared on origin, and
  -- thread counts on files.
  local pull = feature.create({ pull = fixtures.overview, threads = fixtures.threads, cwd = "/tmp/repo" })
  test.eq("main", pull.base, "the PR's base branch")
  test.eq("feat/task-retry-backoff", pull.head, "the PR's head branch")
  test.eq("origin/main", pull.base_rev, "a PR is compared against origin/<base>")
  test.eq("#482 main...feat/task-retry-backoff", feature.title(pull), "the title names the PR")
  pull.loading = false
  pull.files = { { status = "M", path = fixtures.threads[1].path, additions = 1, deletions = 0 } }
  test.contains(text(render(pull)), "#482", "the info section names the PR")
  test.contains(text(render(pull)), "◆", "files with open threads are marked")

  local pending = feature.create({ pull = { number = 77 } })
  test.contains(feature.loading_message(pending), "Loading #77", "a PR waits for its metadata")
  feature.set_pull(pending, { number = 77, base_ref = "develop", head_ref = "fix/x" })
  test.eq("origin/develop", pending.base_rev, "metadata sets the base")
  test.eq("#77 develop...fix/x", pending.diff.title, "the diff pane's title follows")
end
