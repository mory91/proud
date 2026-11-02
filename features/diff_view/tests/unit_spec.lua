return function(test)
  local feature = require("proud.loader").load("diff_view")
  local fixtures = require("proud.fixtures")
  local state = feature.create({
    cwd = "/tmp/repo",
    threads = fixtures.threads,
    title = "#482 main...feat/task-retry-backoff",
    message = "Checking out feat/task-retry-backoff…",
  })
  test.eq("loading", state.status, "a new diff starts loading")
  test.eq("/tmp/repo", state.cwd, "the repository directory is kept")
  state.label = {
    { "main", "ProudAccentText" },
    { "...", "ProudMuted" },
    { "feat/task-retry-backoff", "ProudSuccessText" },
  }

  local loading_bar = feature.winbar(state)
  test.eq("main", loading_bar[1][1], "the window bar starts with the host's label")
  test.eq("ProudSuccessText", loading_bar[3][2], "the head branch is green")
  test.contains(loading_bar[4][1], "loading", "the window bar shows loading before checkout")
  test.contains(table.concat(feature.status_view(state).lines, "\n"), "Checking out feat/task-retry-backoff", "loading shows the host's message")

  state.status = "error"
  state.error = "git checkout feat/task-retry-backoff\nerror: Your local changes to the following files would be overwritten by checkout"
  local error_view = feature.status_view(state)
  test.highlighted(error_view, "Could not open the diff for #482", "ProudDangerText", "errors are headed in the danger color")
  test.contains(table.concat(error_view.lines, "\n"), "would be overwritten by checkout", "git's message is shown verbatim")
  test.contains(feature.winbar(state)[4][1], "could not open", "the window bar reports the error")

  state.status = "empty"
  test.contains(table.concat(feature.status_view(state).lines, "\n"), "No changes in #482", "an empty comparison says so")

  state.status = "ready"
  state.files = {
    { status = "M", path = "packages/runner/src/task/retry.ts" },
    { status = "A", path = "packages/runner/src/config.ts" },
  }
  state.file_cursor = 2
  local bar = feature.winbar(state, { added = 5, deleted = 1 })
  test.contains(bar[4][1], "packages/runner/src/config.ts", "the window bar shows the file path")
  test.eq("[+5 −1]", bar[5][1], "the window bar shows live change counts")
  test.contains(bar[6][1], "2 / 2", "the window bar shows the file position")

  test.contains(feature.thread_preview(state.threads[1]), "◆ dev-lee: attempt is already", "open threads preview their first comment")
  test.truthy(#feature.thread_preview(state.threads[1]) < 60, "previews are shortened")
  local resolved = vim.deepcopy(state.threads[1])
  resolved.resolved = true
  test.eq("   ◇ resolved", feature.thread_preview(resolved), "resolved threads preview as resolved")

  local thread_view = feature.render_thread(state)
  test.highlighted(thread_view, "Thread", "ProudWarning", "open threads use warning color")
  test.highlighted(thread_view, "dev-lee", "ProudAccentText", "comment authors are accented")
  test.truthy(feature.add_reply(state, "Please add a cap."))
  test.eq(3, #state.threads[1].comments)
  feature.next_thread(state, 1)
  test.eq(2, state.thread_cursor)
  test.truthy(feature.resolve(state))
  test.truthy(state.threads[2].resolved)

  local inline = require("proud.ui.inline_diff")
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "a", "B", "c", "d" })
  local stats = inline.decorate(buffer, "x\na\nb\nc\ny\n", { "x", "a", "b", "c", "y" }, 8)
  test.eq(2, stats.added, "inline diff counts added and changed lines")
  test.eq(3, stats.deleted, "inline diff counts deleted lines")
  local above_first, changed_old
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, inline.namespace, 0, -1, { details = true })) do
    local detail = mark[4]
    if detail.virt_lines and mark[2] == 0 and detail.virt_lines_above then
      above_first = vim.trim(detail.virt_lines[1][1][1])
    end
    if detail.virt_lines and mark[2] == 1 then
      changed_old = vim.trim(detail.virt_lines[1][1][1])
    end
  end
  test.eq("x", above_first, "a deleted first line is shown above line 1")
  test.eq("b", changed_old, "a changed line shows its old text above the new one")
  vim.api.nvim_buf_delete(buffer, { force = true })

  -- Diff colors are backgrounds only, so code keeps its syntax colors;
  -- deleted lines get the base text's treesitter colors.
  test.eq(nil, vim.api.nvim_get_hl(0, { name = inline.groups.add, link = false }).fg, "added lines keep their syntax foreground")
  test.eq(nil, vim.api.nvim_get_hl(0, { name = inline.groups.delete, link = false }).fg, "deleted lines keep their syntax foreground")
  local code = vim.api.nvim_create_buf(false, true)
  vim.bo[code].filetype = "lua"
  vim.api.nvim_buf_set_lines(code, 0, -1, false, { "local x = 1" })
  vim.api.nvim_win_set_buf(0, code)
  local handle = inline.attach(code, { base = "local x = 2\n" })
  test.truthy(vim.wait(2000, function() return handle.syntax() and handle.syntax().tree ~= nil end, 5), "the base is parsed in the background")
  local chunks
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(code, inline.namespace, 0, -1, { details = true })) do
    if mark[4].line_hl_group then
      test.eq(inline.groups.add, mark[4].line_hl_group, "added lines use the background-only group")
    end
    chunks = chunks or (mark[4].virt_lines and mark[4].virt_lines[1])
  end
  test.eq({ "local", { inline.groups.delete, "@keyword.lua" } }, chunks[1], "deleted code is colored by its syntax over the delete background")
  test.eq({ "2", { inline.groups.delete, "@number.lua" } }, chunks[7], "each token keeps its own color")
  test.eq(inline.groups.delete, chunks[#chunks][2], "the row is padded with the delete background")
  local plain_syntax = inline.syntax("local x\n", "no_such_language")
  vim.api.nvim_buf_set_lines(code, 0, -1, false, { "local y = 1" })
  handle.refresh()
  local recolored
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(code, inline.namespace, 0, -1, { details = true })) do
    recolored = recolored or (mark[4].virt_lines and mark[4].virt_lines[1][1])
  end
  test.eq({ "local", { inline.groups.delete, "@keyword.lua" } }, recolored, "edits keep the deleted lines colored")
  test.eq(nil, plain_syntax, "languages without a parser fall back to plain deleted lines")
  handle.detach()
  vim.api.nvim_buf_delete(code, { force = true })
end
