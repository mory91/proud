return function(test)
  local ui = require("proud.ui")
  test.eq(5, ui.display_width("abcde"), "ASCII width is byte length")
  test.eq(6, ui.display_width("日本語"), "wide characters take two cells")
  test.eq("abc  ", ui.fit("abc", 5), "fit pads short values")
  test.eq("abcde", ui.fit("abcdefgh", 5), "fit clips ASCII")
  local clipped = ui.fit("日本語テキスト", 5)
  test.eq(5, ui.display_width(clipped), "fit clips wide text to the exact width")
  test.eq("日本 ", clipped, "fit pads when a wide char would overflow")

  local tree = require("proud.components.tree")
  local state = tree.create({ { id = "a", label = "日本語のとても長いラベル" } })
  local view = tree.render(state, 10)
  test.eq(10, ui.display_width(view.lines[1]), "tree rows are fitted with the shared helper")

  local span = ui.view.span
  local lines = { "hello world" }
  local keyed = {}
  test.truthy(span(lines, keyed, 0, "world", "G"), "span reports a found needle")
  test.eq(6, keyed[1].start_col, "keyed span start")
  test.eq(11, keyed[1].end_col, "keyed span end")
  local tuple = {}
  span(lines, tuple, 0, "hello", "G", "tuple")
  test.eq(5, tuple[1][3], "tuple span end")
  local flat = { 9, 9, 9, "X" }
  span(lines, flat, 0, "world", "G", "flat")
  test.eq(8, #flat, "flat span appends four values")
  test.eq("G", flat[8], "flat span group")
  test.truthy(not span(lines, keyed, 0, "", "G"), "empty needles are ignored")
  test.truthy(not span(lines, keyed, 3, "x", "G"), "missing rows are ignored")
  test.eq(1, #keyed, "ignored spans add nothing")
end
