return function(test)
  local feature = require("proud.loader").load("ui_resize")
  local ui = require("proud.ui")
  local function open_pair(list_view, preview_view, prefix)
    return ui.open_pair({
      panes = {
        { name = "list", buffer_name = prefix .. "/list", view = list_view },
        { name = "preview", buffer_name = prefix .. "/preview", view = preview_view },
      },
    })
  end
  local geometry = feature.surface_geometry(120, 40)
  test.eq(3, geometry.gap, "default rounded surface keeps the configured gap")
  test.truthy(geometry.height > 0 and geometry.height <= 34, "surface height remains inside the editor area")
  test.eq(geometry.left_col + geometry.left_width + geometry.gap, geometry.right_col, "panes remain separated")
  local narrow = feature.surface_geometry(40, 24)
  test.eq(1, narrow.gap, "narrow terminals shrink the gap exactly like the renderer")
  test.eq(narrow.left_col + narrow.left_width + narrow.gap, narrow.right_col, "narrow panes remain separated")
  test.eq(40 - 2 - 2, narrow.available_width, "narrow panes fill the available width")
  local widths = feature.workspace_widths({ 0.4, 0.6 }, 101)
  test.eq(2, #widths)
  test.eq(100, widths[1] + widths[2], "workspace widths fill the calculated editor area")
  test.truthy(math.min(unpack(widths)) >= 8, "workspace panes retain a minimum usable width")
  local view = ui.fit_view({ lines = { "short", "a much longer row that must be clipped safely" } }, 12)
  test.eq("short", view.lines[1])
  test.eq("a much longer row that must be clipped safely", view.lines[2])

  local surface = open_pair({ lines = { "owned list" } }, { lines = { "owned preview" } }, "proud://lifecycle-owned")
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

  local before = ui.layout_config()
  local custom = ui.open_pair({
    windows = { gap = 7 },
    panes = {
      { name = "list", buffer_name = "proud://layout-local/list" },
      { name = "preview", buffer_name = "proud://layout-local/preview" },
    },
  })
  test.eq(before.gap, ui.layout_config().gap, "per-surface windows options do not change the global layout")
  local list_config = vim.api.nvim_win_get_config(custom.panes.list.window)
  local preview_config = vim.api.nvim_win_get_config(custom.panes.preview.window)
  test.eq(7, preview_config.col - (list_config.col + list_config.width), "per-surface gap applies to that surface")
  custom.close()
end
