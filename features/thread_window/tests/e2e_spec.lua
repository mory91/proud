return function(test)
  local feature = require("proud.loader").load("thread_window")
  local fixtures = require("proud.fixtures")

  local function keys(value)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(value, true, false, true), "x", false)
  end
  local function lines(buffer)
    return table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
  end
  local function floats(tabpage)
    local found = {}
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
      if vim.api.nvim_win_get_config(window).relative ~= "" then
        found[#found + 1] = window
      end
    end
    return found
  end

  -- A host window with code; the thread sits on line 14.
  local columns = vim.o.columns
  vim.o.columns = 140
  vim.cmd("tabnew")
  local tabpage = vim.api.nvim_get_current_tabpage()
  local window = vim.api.nvim_get_current_win()
  local code = vim.api.nvim_get_current_buf()
  vim.bo[code].buftype = "nofile"
  local text = {}
  for index = 1, 40 do
    text[index] = ("  const line%d = %d"):format(index, index)
  end
  vim.api.nvim_buf_set_lines(code, 0, -1, false, text)
  vim.api.nvim_win_set_cursor(window, { 14, 0 })
  local buffers_before = #vim.api.nvim_list_bufs()

  local thread = vim.deepcopy(fixtures.threads[1])
  local calls = {}
  local answer = { true, nil }
  local changed = 0
  local drafts = {}
  local closed = 0
  local host = {
    window = window,
    row = 13,
    threads = { thread },
    code = text[14],
    author = "sara-k",
    viewer = function() return "morteza" end,
    drafts = drafts,
    act = function(kind, target, body, done)
      calls[#calls + 1] = { kind = kind, thread = target, body = body }
      local ok, result = answer[1], answer[2]
      if ok and not result then
        result = { comment = body and { author = "morteza", age = "now", body = body, pending = kind == "pending" or nil } or nil, resolved = (kind == "resolve" or kind == "resolve_only") or nil }
      end
      vim.schedule(function() done(ok, result) end)
    end,
    on_changed = function() changed = changed + 1 end,
    on_closed = function() closed = closed + 1 end,
  }

  local handle = feature.open(host)
  test.eq(1, #floats(tabpage), "the thread window opens")
  test.eq(window, vim.api.nvim_get_current_win(), "it opens without focus")
  test.contains(lines(handle.buffer), "│ const line14 = 14", "the commented line is quoted")
  test.contains(lines(handle.buffer), "· author", "the PR author's reply is tagged")
  local config = vim.api.nvim_win_get_config(handle.window)
  test.eq(13, config.bufpos[1], "it is anchored to the thread's line")

  -- r opens the reply editor under the thread, focused, in Insert mode.
  handle.focus()
  keys("r")
  local editor = handle.editor
  test.truthy(editor ~= nil, "r opens the reply editor")
  test.eq(editor.window, vim.api.nvim_get_current_win(), "the editor takes focus")
  test.eq("markdown", vim.bo[editor.buffer].filetype, "replies are markdown")
  test.eq(2, #floats(tabpage), "the editor is a second float")
  test.contains(lines(handle.buffer), "Reply as morteza", "the reply header appears")
  local thread_config = vim.api.nvim_win_get_config(handle.window)
  local editor_config = vim.api.nvim_win_get_config(editor.window)
  if thread_config.anchor == "NW" then
    test.eq(thread_config.row + thread_config.height + 2, editor_config.row, "the editor sits right under the thread")
  else
    test.eq(editor_config.row - editor_config.height - 2, thread_config.row, "the editor sits right under the thread, above the line")
  end
  test.truthy(vim.fn.maparg("@", "i", false, true).buffer == 1, "@ completes mentions in the editor")

  -- <C-g> inserts a suggestion with the commented line; <Esc> keeps the draft.
  keys("aAgreed, can we cap it?<CR><C-g><Esc>")
  test.eq(nil, handle.editor, "<Esc> closes the editor")
  test.eq(handle.window, vim.api.nvim_get_current_win(), "focus returns to the thread")
  test.eq("Agreed, can we cap it?\n```suggestion\n  const line14 = 14\n```", drafts[thread.id], "the draft and suggestion are kept")
  test.truthy(not lines(handle.buffer):find("Reply as", 1, true), "the reply header goes with the editor")

  -- Replying again restores the draft; <C-s> posts it.
  keys("r")
  editor = handle.editor
  test.contains(lines(editor.buffer), "```suggestion", "the draft comes back")
  keys("<C-s>")
  test.truthy(vim.wait(1000, function() return handle.editor == nil end, 10), "posting closes the editor")
  test.eq("post", calls[1].kind, "<C-s> posts a reply")
  test.eq(thread, calls[1].thread, "to the thread being replied to")
  test.contains(calls[1].body, "Agreed, can we cap it?", "with the draft's text")
  test.eq(3, #thread.comments, "the reply is added to the thread")
  test.contains(lines(handle.buffer), "Agreed, can we cap it?", "and shown")
  test.eq(nil, drafts[thread.id], "a posted draft is cleared")
  test.eq(1, changed, "the host hears about the change")

  -- A failed post keeps the editor and the text, and shows GitHub's error.
  answer = { false, { message = "HTTP 422: Unprocessable" } }
  local notify = vim.notify
  local notified
  vim.notify = function(message) notified = message end
  keys("r")
  keys("aOne more<C-s>")
  test.truthy(vim.wait(1000, function() return lines(handle.buffer):find("Could not post", 1, true) ~= nil end, 10), "the error is shown")
  vim.notify = notify
  test.contains(lines(handle.buffer), "HTTP 422: Unprocessable", "with GitHub's message")
  test.contains(notified or "", "HTTP 422", "and notified")
  test.truthy(handle.editor ~= nil, "the editor stays open")
  test.eq("One more", lines(handle.editor.buffer), "the text is kept")
  test.eq(3, #thread.comments, "nothing is added")

  -- <C-p> adds to the pending review; <C-r> posts and resolves.
  answer = { true, nil }
  vim.api.nvim_set_current_win(handle.editor.window)
  keys("<C-p>")
  test.truthy(vim.wait(1000, function() return handle.editor == nil end, 10), "the pending reply closes the editor")
  test.eq("pending", calls[#calls].kind, "<C-p> adds to the pending review")
  test.truthy(thread.comments[4].pending, "the reply is shown as pending")
  test.contains(lines(handle.buffer), "· pending", "pending replies are tagged")
  keys("r")
  keys("aDone<C-r>")
  test.truthy(vim.wait(1000, function() return thread.resolved end, 10), "<C-r> resolves the thread")
  test.eq("resolve", calls[#calls].kind, "posting and resolving is one action")
  test.contains(lines(handle.buffer), "◇ ", "the thread shows as resolved")

  -- An empty reply is not posted.
  local count = #calls
  keys("r")
  keys("<C-s>")
  test.eq(count, #calls, "empty replies are not posted")
  test.contains(lines(handle.buffer), "Write a reply first.", "and say why")
  keys("<Esc>")

  -- R resolves without a reply; q closes everything.
  thread.resolved = false
  handle.render()
  vim.api.nvim_set_current_win(handle.window)
  keys("R")
  test.truthy(vim.wait(1000, function() return thread.resolved end, 10), "R resolves the thread")
  test.eq("resolve_only", calls[#calls].kind)
  keys("r")
  keys("aunsent<Esc>")
  vim.api.nvim_set_current_win(handle.window)
  keys("q")
  test.truthy(handle.closed, "q closes the thread window")
  test.eq(1, closed, "the host hears it closed")
  test.eq(0, #floats(tabpage), "no float is left")
  test.eq(window, vim.api.nvim_get_current_win(), "focus returns to the code")
  test.eq("unsent", drafts[thread.id], "closing keeps the draft")
  test.eq(buffers_before, #vim.api.nvim_list_bufs(), "the window's buffers are wiped")

  -- Leaving for another window closes it; so does moving off the line.
  handle = feature.open(host, { focus = true })
  handle.reply()
  vim.cmd("stopinsert")
  vim.api.nvim_set_current_win(window)
  test.truthy(vim.wait(1000, function() return handle.closed end, 10), "leaving the window closes it")
  test.eq("unsent", drafts[thread.id], "the draft survives")
  handle = feature.open(host)
  vim.api.nvim_win_set_cursor(window, { 20, 0 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = code })
  test.truthy(handle.closed, "moving off the line closes it")

  -- Near the bottom of the window it opens above the line.
  vim.api.nvim_win_set_cursor(window, { 40, 0 })
  vim.cmd("normal! zb")
  host.row = 39
  handle = feature.open(host)
  test.eq("SW", vim.api.nvim_win_get_config(handle.window).anchor, "near the bottom it opens above the line")
  handle.close()

  vim.cmd("tabclose")
  vim.o.columns = columns
end
