return function(test)
  local feature = require("proud.loader").load("single_diff_threads")
  local fixtures = require("proud.fixtures")
  local state = feature.create(fixtures.overview, fixtures.threads, fixtures.patch, fixtures.file_sources)
  local placeholder = feature.create({ number = 902 }, {}, nil, {})
  placeholder.loading = true
  test.contains(feature.render_code(placeholder).lines[1], "Loading diff", "diff placeholder renders before patch data")
  feature.hydrate(placeholder, { pull = fixtures.overview })
  test.truthy(placeholder.loading, "pull hydration leaves the diff loading until its patch arrives")
  feature.hydrate(placeholder, { patch = fixtures.patch })
  test.truthy(not placeholder.loading, "patch hydration clears diff loading")
  feature.hydrate(placeholder, { threads = fixtures.threads })
  test.eq(2, #placeholder.threads, "threads hydrate independently without rebuilding the scene")
  local rendered = table.concat(feature.render_code(state).lines, "\n")
  test.contains(rendered, "export interface RetryConfig")
  test.contains(rendered, "throw new Error(\"retry exhausted\")")
  test.contains(rendered, "await sleep(1000)")
  test.contains(rendered, "const delay = baseDelayMs * 2 ** (attempt - 1)")
  local panes = feature.render_panes(state)
  test.eq(nil, panes.files, "the single-pane diff has no files pane")
  test.eq(nil, panes.thread, "the single-pane diff has no thread pane")
  test.highlighted(panes.code, "await sleep(1000)", "ProudDelete", "deleted source is danger-colored")
  test.highlighted(panes.code, "const delay", "ProudAdd", "added source is success-colored")
  test.highlighted(panes.code, "◆", "ProudWarning", "open threads mark the sign column")
  local thread_row = state.thread_rows[state.threads[1]]
  test.truthy(thread_row ~= nil, "thread rows are recorded for navigation")
  local thread_line = panes.code.lines[thread_row + 1]
  test.eq("  14", thread_line:sub(6, 9), "the new line number column shows the thread's line")
  test.eq("◆", thread_line:sub(11, 13), "the sign column shows the thread marker")
  local added_row
  for row, line in ipairs(panes.code.lines) do
    if line:find("export interface RetryConfig", 1, true) then
      added_row = line
    end
    if line:find("await sleep(1000)", 1, true) then
      test.eq("    ", line:sub(6, 9), "deleted rows have no new line number")
      test.truthy(line:sub(1, 4):match("%d") ~= nil, "deleted rows keep their old line number")
      test.eq("-", line:sub(11, 11), "deleted rows show a minus sign")
    end
  end
  test.truthy(added_row ~= nil, "the full file is rendered")
  local preview
  local virtual = panes.code.virtual or {}
  for index = 1, #virtual, 3 do
    if virtual[index] == thread_row then
      preview = virtual[index + 1]
    end
  end
  test.contains(preview or "", "◆ dev-lee: attempt is already", "open threads preview their first comment at the line end")
  local bar = feature.winbar(state)
  test.eq("main", bar[1][1], "the window bar starts with the base branch")
  test.eq("ProudSuccessText", bar[3][2], "the head branch is green")
  test.contains(bar[4][1], "packages/runner/src/task/retry.ts", "the window bar shows the file path")
  test.contains(bar[6][1], "1 / ", "the window bar shows the file position")
  local thread_view = feature.render_thread(state)
  test.highlighted(thread_view, "Thread", "ProudWarning", "open threads use warning color")
  test.highlighted(thread_view, "dev-lee", "ProudAccentText", "comment authors are accented")
  test.truthy(feature.add_reply(state, "Please add a cap."))
  test.eq(3, #state.threads[1].comments)
  feature.next_thread(state, 1)
  test.eq(2, state.thread_cursor)
  test.truthy(feature.resolve(state))
  test.truthy(state.threads[2].resolved)
  test.contains(table.concat(feature.render(state).lines, "\n"), "resolved")
  state.file_cursor = 2
  local resolved_preview
  local config_view = feature.render_code(state)
  local config_virtual = config_view.virtual or {}
  for index = 1, #config_virtual, 3 do
    resolved_preview = config_virtual[index + 1]
  end
  test.eq("   ◇ resolved", resolved_preview, "resolved threads preview as resolved")
end
