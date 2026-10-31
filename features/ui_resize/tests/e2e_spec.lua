return function(test)
  local feature = require("proud.loader").load("ui_resize")
  local ui = require("proud.ui")
  local keymap = require("proud.keymap")
  local surface = ui.open_rounded_pair({ list = { lines = { "list row" } }, preview = { lines = { "preview row" } } }, {
    list_name = "proud://resize/list",
    preview_name = "proud://resize/preview",
  })
  local expected = feature.surface_geometry(vim.o.columns, vim.o.lines)
  test.truthy(feature.validate_surface(surface, expected), "rounded surface starts with live geometry")
  vim.o.columns = math.max(40, vim.o.columns - 8)
  vim.o.lines = math.max(12, vim.o.lines - 2)
  surface.resize()
  expected = feature.surface_geometry(vim.o.columns, vim.o.lines)
  test.truthy(feature.validate_surface(surface, expected), "rounded surface relayouts after a terminal shrink")
  vim.o.columns = vim.o.columns + 8
  vim.o.lines = vim.o.lines + 2
  surface.resize()
  expected = feature.surface_geometry(vim.o.columns, vim.o.lines)
  test.truthy(feature.validate_surface(surface, expected), "rounded surface restores after a terminal grow")
  vim.cmd("tabclose!")
  local renders = 0
  local workspace
  workspace = ui.open_workspace("proud://resize/workspace", {
    { name = "left", buffer_name = "proud://resize/workspace/left", view = { lines = { "left resized" } }, weight = 0.4 },
    { name = "right", buffer_name = "proud://resize/workspace/right", view = { lines = { "right resized" } }, weight = 0.6 },
  }, {
    render = function()
      renders = renders + 1
    end,
  })
  local widths = feature.workspace_widths({ 0.4, 0.6 }, vim.o.columns)
  test.truthy(feature.validate_workspace(workspace, widths), "workspace starts with calculated widths")
  test.truthy(feature.resize_workspace(workspace), "workspace resize entry point refreshes content")
  test.truthy(renders == 1, "workspace resize callback re-renders once")
  test.contains(table.concat(vim.api.nvim_buf_get_lines(workspace.panes.left.buffer, 0, -1, false), "\n"), "left resized")
  vim.cmd("tabclose!")

  local deleted_surface = ui.open_rounded_pair({
    list = { lines = { "delete target" } },
    preview = { lines = { "delete companion" } },
  }, {
    list_name = "proud://lifecycle-delete/list",
    preview_name = "proud://lifecycle-delete/preview",
  })
  local deleted_tabpage = deleted_surface.tabpage
  vim.api.nvim_buf_delete(deleted_surface.panes.list.buffer, { force = true })
  test.truthy(vim.wait(1000, deleted_surface.lifecycle.closed, 10), "deleting an owned buffer closes its scene")
  test.truthy(not vim.api.nvim_tabpage_is_valid(deleted_tabpage), "buffer deletion closes the whole scene tabpage")

  local quit_surface = ui.open_rounded_pair({
    list = { lines = { "quit target" } },
    preview = { lines = { "quit companion" } },
  }, {
    list_name = "proud://lifecycle-quit/list",
    preview_name = "proud://lifecycle-quit/preview",
  })
  local quit_tabpage = quit_surface.tabpage
  keymap.bind_common_buffer(quit_surface.panes.preview.buffer, { on_quit = quit_surface.close })
  vim.api.nvim_buf_delete(quit_surface.panes.list.buffer, { force = true })
  vim.api.nvim_feedkeys("q", "x", false)
  test.truthy(vim.wait(1000, quit_surface.lifecycle.closed, 10), "q still closes a scene after its first buffer is deleted")
  test.truthy(not vim.api.nvim_tabpage_is_valid(quit_tabpage), "post-delete quit leaves no half-open scene")
end
