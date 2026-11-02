return function(test)
  local feature = require("proud.loader").load("thread_window")
  local fixtures = require("proud.fixtures")

  local thread = vim.deepcopy(fixtures.threads[1])
  thread.comments[2].body = "First paragraph that is long enough to wrap across more than one line of the window.\n\nSecond paragraph."
  thread.comments[3] = { author = "morteza", age = "now", body = "Later.", pending = true }
  local view, starts = feature.view({ thread }, 40, {
    author = "sara-k",
    code = "      const delay = baseDelayMs * 2 ** attempt",
  })
  local text = table.concat(view.lines, "\n")
  test.eq({ 1 }, starts, "the thread's header row is reported")
  test.highlighted(view, "◆", "ProudWarning", "open threads use warning color")
  test.highlighted(view, "unresolved", "ProudDangerText", "the thread's state is shown")
  test.contains(text, "3 comments", "comments are counted")
  test.contains(view.lines[2], "│ const delay = baseDelayMs", "the commented line is quoted under the header")
  test.highlighted(view, "dev-lee", "ProudAccentText", "comment authors are accented")
  test.contains(text, "Intended?", "the first comment is shown in full")
  test.contains(text, "↳ sara-k", "replies are marked")
  test.contains(text, "· author", "the pull request's author is tagged")
  test.contains(text, "Second paragraph.", "every paragraph is shown")
  test.highlighted(view, "  · pending", "ProudWarning", "pending review comments are tagged")
  for row = 3, #view.lines do
    test.truthy(vim.fn.strdisplaywidth(view.lines[row]) <= 40, "comments are wrapped to the window: " .. view.lines[row])
  end
  test.truthy(not text:find("Reply as", 1, true), "no reply header until replying")

  local resolved = vim.deepcopy(fixtures.threads[2])
  resolved.resolved = true
  resolved.outdated = true
  local two, two_starts = feature.view({ fixtures.threads[1], resolved }, 60)
  test.eq(2, #two_starts, "each thread on the line has a header")
  test.highlighted(two, "resolved", "ProudSuccessText", "resolved threads are shown as resolved")
  test.highlighted(two, "  · outdated", "ProudWarning", "outdated threads are marked")

  -- The reply header, as in the design.
  local replying = feature.view({ fixtures.threads[1] }, 84, {
    replying = fixtures.threads[1],
    viewer = "morteza",
    status = { "Could not post: HTTP 422", "ProudDangerText" },
  })
  local reply_text = table.concat(replying.lines, "\n")
  test.contains(reply_text, "Reply as morteza  · markdown  · @ mention  <C-g> insert suggestion", "the reply header names the viewer and keys")
  test.highlighted(replying, " Reply as morteza", "ProudAccentText", "the reply header is accented")
  test.highlighted(replying, "Could not post: HTTP 422", "ProudDangerText", "errors are shown under the header")
  test.contains(table.concat(feature.view({ thread }, 84, { replying = thread }).lines, "\n"), "Reply as you", "without a login it says you")
  local narrow = feature.view({ thread }, 46, { replying = thread, viewer = "morteza" })
  test.contains(table.concat(narrow.lines, "\n"), "Reply as morteza  · @ mention · <C-g> suggest", "narrow windows get a shorter reply header")
  test.truthy(vim.fn.strdisplaywidth(narrow.lines[#narrow.lines]) <= 46, "the short header fits")

  test.eq({ "dev-lee", "sara-k" }, feature.participants({ fixtures.threads[1] }, "sara-k", "morteza"), "@ offers the participants and the author once")
  test.eq({ "sara-k" }, feature.participants({ fixtures.threads[1] }, nil, "dev-lee"), "the viewer is not offered")
end
