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

  local v = ui.view.new()
  local row = v:line({ "base", "G1" }, "  ", { "database-fix", "G2" }, " ", { "base", "G3" })
  test.eq(0, row, "line returns its row")
  local built = v:build()
  test.eq("flat", built.highlight_format, "builder emits flat highlights")
  test.eq("base  database-fix base", built.lines[1], "chunks are concatenated")
  test.eq(19, built.highlights[10], "repeated words keep their own exact columns")
  test.eq("G3", built.highlights[12], "third chunk keeps its group")

  local wide = ui.view.new()
  wide:line({ "日本", "W" }, { "x", "X" })
  test.eq(6, wide:build().highlights[3], "wide characters use byte columns")
  test.eq(6, wide.highlights[6], "following chunk starts after the wide text")

  local fitted = ui.view.new({ width = 4 })
  fitted:line({ "abcdef", "A" }, { "gh", "B" })
  local fv = fitted:build()
  test.eq("abcd", fv.lines[1], "width clips the line")
  test.eq(4, fv.highlights[3], "width clips highlight ends")
  test.eq(4, fv.highlights[6], "highlights past the clip become empty")
  fitted:rule("R")
  test.eq(string.rep("─", 4), fv.lines[2], "rule uses the view width")

  local hot = ui.view.new()
  hot:open()
  hot:add("a", "A"):add("bc"):add("d", "D")
  test.eq(0, hot:close(), "open/add/close returns the row")
  test.eq("abcd", hot:build().lines[1], "open/add/close builds the line")
  test.eq(3, hot.highlights[6], "open/add/close tracks columns")

  local compare = require("proud.loader").load("branch_compare")
  local loading = compare.render(compare.create({ base = "main", head = "feature", loading = true }))
  test.highlighted(loading, "Files", "ProudAccentText", "the Files heading is highlighted while loading")

  local spanned = ui.view.new()
  test.eq(0, spanned:spans("The token is ", nil, "hidden", "G", "."), "spans returns its row")
  local sv = spanned:build()
  test.eq("The token is hidden.", sv.lines[1], "spans joins alternating text")
  test.eq(13, sv.highlights[2], "spans records exact start columns")
  test.eq(19, sv.highlights[3], "spans records exact end columns")
  test.eq(4, #sv.highlights, "spans skips nil groups")
end
