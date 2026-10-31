return function(test)
  local keymap = require("proud.keymap")
  local feature = require("proud.loader").load("sidebar")
  local overview = require("proud.loader").load("pull_request_overview")
  local tree = require("proud.components.tree")
  local fixtures = require("proud.fixtures")
  keymap.setup({ next_item = "J", previous_item = "K" })
  local overview_state = overview.create(fixtures.overview)
  local opened
  local buffer, workspace = feature.open(overview_state.sidebar, {
    name = "proud://sidebar-e2e",
    title = "Sidebar",
    width = 48,
    on_open = function(file)
      opened = file.path
    end,
    on_toggle_viewed = function(path)
      overview.mark_viewed(overview_state, path)
    end,
  })
  test.truthy(vim.api.nvim_buf_is_valid(buffer))
  test.eq(1, #workspace.order, "generic sidebar opens as one independent Vim pane")
  local text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
  test.contains(text, "Files 5 · 1 of 5 viewed")
  test.contains(text, "Commits 6")
  test.contains(text, "Checks 4 of 5 passing")
  test.contains(text, "✓ lint                 18s")
  test.contains(text, "✗ e2e / robot-studio   6m 40s")
  test.contains(text, "a3f91c2 Use config for retry limits")

  local selection_refreshes = 0
  local original_refresh = overview_state.sidebar.refresh
  overview_state.sidebar.refresh = function()
    selection_refreshes = selection_refreshes + 1
    return original_refresh()
  end
  vim.api.nvim_feedkeys("j", "x", false)
  test.eq("runTask.ts", tree.selected(overview_state.sidebar).label, "j selects the next visible entry")
  test.eq(0, selection_refreshes, "j does not repaint the sidebar through the structural refresh path")
  vim.api.nvim_feedkeys("k", "x", false)
  test.eq("retry.ts", tree.selected(overview_state.sidebar).label, "k selects the previous visible entry")
  test.eq(0, selection_refreshes, "k does not repaint the sidebar through the structural refresh path")
  overview_state.sidebar.refresh = original_refresh

  for _ = 1, 20 do
    if tree.selected(overview_state.sidebar).id == "commits" then
      break
    end
    vim.api.nvim_feedkeys("j", "x", false)
  end
  test.eq("commits", tree.selected(overview_state.sidebar).id, "j reaches the expandable commit branch")
  local commit_row
  for row, line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
    if line:find("Commits 6", 1, true) then
      commit_row = row
      break
    end
  end
  test.truthy(commit_row ~= nil, "commit branch has a visible buffer row")
  overview_state.sidebar.selected_id = "files"
  vim.api.nvim_win_set_cursor(workspace.panes.sidebar.window, { commit_row, 0 })
  vim.cmd("doautocmd CursorMoved")
  test.eq("commits", tree.selected(overview_state.sidebar).id, "native cursor movement synchronizes the exact selected node")
  vim.api.nvim_feedkeys("c", "x", false)
  text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
  test.truthy(not text:find("a3f91c2", 1, true), "c collapses the branch under the cursor")
  vim.api.nvim_feedkeys("l", "x", false)
  text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
  test.contains(text, "a3f91c2 Use config for retry limits", "l expands the selected branch")
  vim.api.nvim_feedkeys("c", "x", false)
  text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
  test.truthy(not text:find("a3f91c2", 1, true), "c collapses the selected branch")
  vim.api.nvim_feedkeys("o", "x", false)
  text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
  test.contains(text, "a3f91c2 Use config for retry limits", "o expands the selected branch")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Space>", true, false, true), "x", false)
  text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
  test.truthy(not text:find("a3f91c2", 1, true), "space collapses the selected header")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Space>", true, false, true), "x", false)
  text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
  test.contains(text, "a3f91c2 Use config for retry limits", "space expands the selected header")

  test.truthy(feature.select_file(overview_state.sidebar, "packages/runner/src/task/retry.ts"))
  overview_state.sidebar.refresh()
  vim.api.nvim_feedkeys("v", "x", false)
  test.truthy(overview_state.files[1].viewed, "viewed action updates the composed file state")
  overview_state.sidebar.refresh()
  text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
  test.contains(text, "Files 5 · 2 of 5 viewed", "viewed action updates the file header status")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
  test.eq("packages/runner/src/task/retry.ts", opened, "enter opens the selected file")
  vim.cmd("silent! tabclose!")
  keymap.setup()
end
