return function(test)
  local feature = require("proud.loader").load("ui_resize")
  local ui = require("proud.ui")
  local geometry = feature.surface_geometry(120, 40)
  test.eq(3, geometry.gap, "default rounded surface keeps the configured gap")
  test.truthy(geometry.height > 0 and geometry.height <= 34, "surface height remains inside the editor area")
  test.eq(geometry.left_col + geometry.left_width + geometry.gap, geometry.right_col, "panes remain separated")
  local widths = feature.workspace_widths({ 0.4, 0.6 }, 101)
  test.eq(2, #widths)
  test.eq(100, widths[1] + widths[2], "workspace widths fill the calculated editor area")
  test.truthy(math.min(unpack(widths)) >= 8, "workspace panes retain a minimum usable width")
  local view = ui.fit_view({ lines = { "short", "a much longer row that must be clipped safely" } }, 12)
  test.eq("short", view.lines[1])
  test.eq("a much longer row that must be clipped safely", view.lines[2])

  local surface = ui.open_rounded_pair({
    list = { lines = { "owned list" } },
    preview = { lines = { "owned preview" } },
  }, {
    list_name = "proud://lifecycle-owned/list",
    preview_name = "proud://lifecycle-owned/preview",
  })
  local tabpage = surface.tabpage
  local list_buffer = surface.panes.list.buffer
  local list_window = surface.panes.list.window
  test.truthy(surface.lifecycle.scene_id == vim.t[tabpage].proud_scene_id, "surface tabpage is scene-tagged")
  vim.t[tabpage].proud_scene_id = "replacement_scene"
  vim.b[list_buffer].proud_scene_id = "replacement_scene"
  vim.w[list_window].proud_scene_id = "replacement_scene"
  surface.lifecycle.request_close()
  test.truthy(vim.wait(1000, surface.lifecycle.closed, 10), "deferred scene cleanup completes")
  test.truthy(vim.api.nvim_tabpage_is_valid(tabpage), "deferred cleanup leaves a replacement tabpage alone")
  test.truthy(vim.api.nvim_buf_is_valid(list_buffer), "deferred cleanup leaves a replacement buffer alone")
  test.truthy(vim.api.nvim_win_is_valid(list_window), "deferred cleanup leaves a replacement window alone")
  vim.cmd("tabclose!")
end
