return function(test)
  local row = require("proud.components.section_row")
  local tree = require("proud.components.tree")
  local feature = require("proud.loader").load("sidebar")

  local line, highlights = row.render({
    { text = "asx5xv6", group = "ProudAccentText" },
    { text = "commit message", group = "ProudBright" },
  }, 1)
  test.eq("asx5xv6 commit message", line, "commit group uses one space between two sections")
  test.eq(2, #highlights)

  line = row.render({
    { text = "name" },
    { text = "+43-110" },
    { text = "◆2" },
    { text = "viewed" },
  }, { 2, 3, 1 })
  test.eq("name  +43-110   ◆2 viewed", line, "each group can define every section gap")

  line = row.render({
    { text = "abc1234" },
    { text = "Commit subject\nDetailed body" },
  }, 1)
  test.eq("abc1234 Commit subject Detailed body", line, "composed rows always stay on one buffer line")

  local valid = pcall(row.render, {
    { text = "1" },
    { text = "2" },
    { text = "3" },
    { text = "4" },
    { text = "5" },
  }, 1)
  test.truthy(valid, "five sections are supported")
  local too_many = pcall(row.render, {
    { text = "1" },
    { text = "2" },
    { text = "3" },
    { text = "4" },
    { text = "5" },
    { text = "6" },
  }, 1)
  test.truthy(not too_many, "six sections are rejected")

  local state = tree.create({
    {
      id = "root",
      label = "Root",
      expanded = false,
      children = {
        {
          id = "child",
          label = "Child",
          children = { { id = "leaf", label = "Leaf" } },
        },
      },
    },
  })
  test.eq(1, #tree.flatten(state), "collapsed nodes hide every descendant")
  test.truthy(tree.expand(state), "the selected branch can be expanded directly")
  test.eq(2, #tree.flatten(state), "expand reveals the selected branch")
  test.truthy(tree.collapse(state), "the selected branch can be collapsed directly")
  test.eq(1, #tree.flatten(state), "collapse hides the selected branch again")
  test.truthy(tree.toggle(state, "root"))
  test.eq(2, #tree.flatten(state), "expanding a node reveals its direct visible children")
  test.truthy(tree.toggle(state, "child"))
  test.eq(3, #tree.flatten(state), "nested nodes expand independently")
  test.truthy(tree.move(state, 2))
  test.eq("leaf", tree.selected(state).id, "navigation follows visible tree order")
  test.truthy(tree.move(state, -1))
  test.eq("child", tree.selected(state).id, "backwards navigation follows visible tree order")
  test.eq("leaf", tree.select_row(state, 3).id, "cursor rows map to their exact visible node")
  test.eq("leaf", tree.selected(state).id, "cursor selection becomes the action target")
  test.eq(nil, tree.select_row(state, 99), "out-of-range cursor rows do not change selection")

  local callback_kinds = {}
  local moved = feature.move_selection(tree.create({
    { id = "first", label = "First" },
    { id = "second", label = "Second" },
  }), 1, {
    on_change = function(kind)
      table.insert(callback_kinds, kind)
    end,
  })
  test.truthy(moved, "selection movement succeeds for a visible node")
  test.eq({ "selection" }, callback_kinds, "selection movement reports only a selection change")
  tree.select(state, "root")
  tree.collapse(state)
  local layout = tree.layout(state)
  test.eq("root", layout.selected_id, "tree layout records the active node")
  test.eq(false, layout.expanded.root, "tree layout records collapsed branches")
  local rebuilt = tree.create({
    {
      id = "root",
      label = "Root",
      expanded = true,
      children = { { id = "child", label = "Child", children = { { id = "leaf", label = "Leaf" } } } },
    },
  })
  tree.restore_layout(rebuilt, layout)
  test.eq("root", tree.selected(rebuilt).id, "layout restoration keeps the selected node")
  test.eq(false, rebuilt.roots[1].expanded, "layout restoration preserves explicit branch collapse")
  local empty_header = tree.create({
    { id = "empty", kind = "header", label = "Empty", expanded = true, children = {} },
  })
  test.truthy(tree.toggle(empty_header), "empty headers remain toggleable while children load")
  test.eq(false, empty_header.roots[1].expanded)
  test.truthy(tree.toggle(empty_header), "collapsed empty headers can reopen")
  test.eq(true, empty_header.roots[1].expanded)
  local marker_free = tree.create({
    {
      id = "root",
      label = "Root",
      expanded = true,
      children = {
        { id = "row", label = "Row", marker = "", sections = { { text = "✓ Row" } } },
      },
    },
  })
  test.eq("  ✓ Row", tree.render(marker_free).lines[2], "nodes can suppress the generic leaf marker")
  local keymap = require("proud.keymap")
  test.eq({ "j" }, keymap.keys("next_node"), "tree navigation keeps j independent of PR-list navigation")
  test.eq({ "k" }, keymap.keys("previous_node"), "tree navigation keeps k independent of PR-list navigation")
  test.eq({ "l", "o" }, keymap.keys("expand_node"), "branch expansion exposes directional and open aliases")
  test.eq({ "h", "c" }, keymap.keys("collapse_node"), "branch collapse exposes directional and close aliases")

  local overview = require("proud.loader").load("pull_request_overview")
  local fixtures = require("proud.fixtures")
  local overview_state = overview.create(fixtures.overview)
  local nodes = feature.overview_nodes(overview_state)
  test.eq({ "files", "commits", "checks" }, { nodes[1].id, nodes[2].id, nodes[3].id })
  test.eq("Files", nodes[1].sections[1].text, "file header label comes first")
  test.eq("5 · 1 of 5 viewed", nodes[1].sections[2].text, "file metadata follows the shared header pattern")
  test.eq("ProudBright", nodes[1].sections[1].parts[1].group, "header labels are white")
  test.eq("ProudMuted", nodes[1].sections[2].parts[1].group, "header metadata is grey")
  test.eq("6", nodes[2].sections[2].text, "commit metadata carries the item count")
  test.eq("4 of 5 passing", nodes[3].sections[2].text, "check metadata uses the passing summary")
  test.eq("", nodes[3].children[1].marker, "check status symbols replace generic tree markers")
  local rendered = feature.render(overview_state.sidebar, 48)
  local rendered_text = table.concat(rendered.lines, "\n")
  test.contains(rendered_text, "a3f91c2 Use config for retry limits")
  test.contains(rendered_text, "Checks 4 of 5 passing")
  test.contains(rendered_text, "✓ lint                 18s")
  test.contains(rendered_text, "✗ e2e / robot-studio   6m 40s")
  test.highlighted(rendered, "lint", "ProudBright", "check names are bright")
  test.highlighted(rendered, "18s", "ProudMuted", "check durations are muted")
  test.highlighted(rendered, "✓", "ProudSuccessText", "passing checks use success color")
  test.highlighted(rendered, "✗", "ProudDangerText", "failed checks use danger color")
  test.truthy(nodes[2].children[1].spacing == 1, "commit rows use commit-group spacing")
  test.truthy(nodes[1].children[1].children[1].spacing[1] == 2, "file rows use file-group spacing")

  local composed = feature.create(feature.overview_nodes({
    files = {
      {
        path = "src/retry.ts",
        additions = 43,
        deletions = 110,
        threads = 2,
        viewed = true,
      },
    },
    commits = {},
    checks = {},
  }))
  local file_node = tree.find(composed, "file:src/retry.ts")
  test.eq(4, #file_node.sections, "a fully annotated file uses name, changes, comments, and viewed sections")
  test.eq("retry.ts", file_node.sections[1].text)
  test.eq(2, #file_node.sections[2].parts, "one changes section contains colored addition and deletion spans")
  test.eq("◆2", file_node.sections[3].text)
  test.eq("viewed", file_node.sections[4].text)
end
