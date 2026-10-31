return function(test)
  local feature = require("proud.loader").load("branch_compare")
  local fixtures = require("proud.fixtures")
  local state = feature.create(fixtures.compare)
  local view = feature.render(state)
  test.contains(table.concat(view.lines, "\n"), "Files  5  +284  -61")
  local panes = feature.render_panes(state)
  test.highlighted(panes.summary, "Compare", "ProudAccentText", "compare heading is accented")
  test.highlighted(panes.summary, "ahead", "ProudSuccessText", "ahead state is successful")
  test.highlighted(panes.summary, "behind", "ProudWarning", "behind state warns")
  test.highlighted(panes.changes, "9a7d3f0", "ProudAccentText", "commit IDs are accented")
  test.highlighted(panes.changes, "+44", "ProudSuccessText", "file additions are successful")
  test.highlighted(panes.changes, "-22", "ProudDangerText", "file deletions are dangerous")
  feature.swap(state)
  test.eq("feat/monitor-diffs", state.base)
  test.eq(3, state.ahead)
  feature.toggle_mode(state)
  test.eq("two-dot", state.mode)

  local placeholder = feature.create({ base = "main", head = "feature", loading = true })
  test.contains(table.concat(feature.render(placeholder).lines, "\n"), "Loading comparison...", "compare placeholder renders before git data")
  feature.hydrate(placeholder, fixtures.compare)
  test.truthy(not placeholder.loading, "comparison hydration clears its loading state")
  test.contains(table.concat(feature.render(placeholder).lines, "\n"), "Files  5  +284  -61")

  local swapped_placeholder = feature.create({ base = "main", head = "feature", loading = true })
  feature.swap(swapped_placeholder)
  feature.hydrate(swapped_placeholder, {
    base = "main",
    head = "feature",
    ahead = 12,
    behind = 3,
  })
  test.eq("feature", swapped_placeholder.base)
  test.eq("main", swapped_placeholder.head)
  test.eq(3, swapped_placeholder.ahead, "hydration reverses ahead count after an async window swap")
  test.eq(12, swapped_placeholder.behind, "hydration reverses behind count after an async window swap")
end
