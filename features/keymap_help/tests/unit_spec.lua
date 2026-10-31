return function(test)
  local feature = require("proud.loader").load("keymap_help")
  local keymap = require("proud.keymap")
  keymap.setup({
    help = "<F1>",
    open_diff = { "x", "X" },
    expand_node = "o",
    collapse_node = "c",
  })
  test.eq({ "o" }, keymap.keys("expand_node"), "branch expansion keys are configurable")
  test.eq({ "c" }, keymap.keys("collapse_node"), "branch collapse keys are configurable")
  local state = feature.create()
  local rendered = table.concat(feature.render(state).lines, "\n")
  test.contains(rendered, "Pull request list")
  test.contains(rendered, ":Proud compare {base} {head}")
  test.contains(rendered, "bindings shown here are configurable")
  test.contains(rendered, "<F1>")
  test.contains(rendered, "x / X")
  test.contains(rendered, "Focus the pull request preview")
  test.contains(rendered, "Return to the pull request list")
  test.contains(rendered, "Expand the selected sidebar branch")
  test.contains(rendered, "Collapse the selected sidebar branch")
  local panes = feature.render_panes(state)
  test.highlighted(panes.bindings, "Pull request list", "ProudAccentText", "help section headings are accented")
  test.highlighted(panes.bindings, "<F1>", "ProudBright", "configured keycaps are bright")
  test.highlighted(panes.bindings, "Toggle this help", "ProudMuted", "descriptions are muted")
  test.highlighted(panes.commands, ":Proud prs", "ProudBright", "commands are bright")
  test.highlighted(panes.runtime, "independent panes.", "ProudSuccessText", "pane contract is successful")
  keymap.setup()
end
