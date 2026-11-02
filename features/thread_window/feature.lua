-- Thread window: the review threads on one diff line, in full, in a float
-- beside that line; and the reply editor under them (design screen 4).
--
--   ╭ Thread ──────────────────────────────────────────╮
--   │ ◆ retry.ts:14  · unresolved  · 2 comments         │
--   │ │ const delay = baseDelayMs * 2 ** attempt        │
--   │ dev-lee  · 1h ago                                 │
--   │ attempt is already incremented here, …            │
--   │   ↳ sara-k  · 40m ago · author                    │
--   │ ───────────────────────────────────────────────── │
--   │ Reply as morteza · markdown · @ mention  <C-g> …  │
--   ╰───────────────────────────────────────────────────╯
--   ╭───────────────────────────────────────────────────╮
--   │ Agreed. While you're in here, can we also cap it? │   (editable)
--   ╰ <C-s> post  <C-r> post and resolve  <C-p> …  ─────╯
--
-- The window is host-agnostic: the diff pane passes the line, the threads
-- and the actions that talk to GitHub.
local ui = require("proud.ui")
local keymap = require("proud.keymap")
local composer = require("proud.ui.composer")

local M = {
  name = "thread_window",
}

M.width = 84
local sequence = 0
local trim = composer.trim

-- Text of `threads` (all on one line), wrapped to `width` cells.
-- options:
--   author    the pull request's author: their comments are tagged
--   code      the commented line's text, quoted under the first header
--   replying  the thread being replied to: adds the reply header
--   viewer    login shown in "Reply as …"
--   status    { text, group } under the reply header (posting, errors)
-- Returns the view and, per thread, the 1-based row its header is on.
function M.view(threads, width, options)
  options = options or {}
  width = math.max(20, math.floor(width or M.width))
  local v = ui.view.new()
  local starts = {}
  for index, thread in ipairs(threads) do
    if index > 1 then
      v:blank()
    end
    starts[index] = #v.lines + 1
    local resolved = thread.resolved
    local comments = thread.comments or {}
    v:spans(
      " ", nil,
      resolved and "◇ " or "◆ ", resolved and "ProudSuccessText" or "ProudWarning",
      vim.fn.fnamemodify(thread.path or "", ":t") .. ":" .. tostring(thread.line or "?"), "ProudBright",
      "  · ", "ProudMuted",
      resolved and "resolved" or "unresolved", resolved and "ProudSuccessText" or "ProudDangerText",
      ("  · %d comment%s"):format(#comments, #comments == 1 and "" or "s"), "ProudMuted",
      thread.outdated and "  · outdated" or "", "ProudWarning"
    )
    if index == 1 and options.code and options.code ~= "" then
      v:spans(" │ ", "ProudMuted", ui.fit(vim.trim(options.code), width - 4), "ProudText")
    end
    for position, comment in ipairs(comments) do
      -- Replies are indented under the comment that opened the thread.
      local indent = position == 1 and " " or "   "
      v:blank()
      v:spans(
        indent, nil,
        position == 1 and "" or "↳ ", "ProudMuted",
        tostring(comment.author or "unknown"), "ProudAccentText",
        "  · " .. tostring(comment.age or ""), "ProudMuted",
        options.author and comment.author == options.author and " · author" or "", "ProudMuted",
        comment.pending and "  · pending" or "", "ProudWarning"
      )
      local body = tostring(comment.body or "")
      if body == "" then
        v:spans(indent, nil, "(no message)", "ProudMuted")
      end
      local body_indent = position == 1 and indent or indent .. "  "
      for paragraph in (body .. "\n"):gmatch("(.-)\r?\n") do
        if paragraph == "" then
          if body ~= "" then
            v:blank()
          end
        else
          for _, line in ipairs(ui.wrap_text(paragraph, width - #body_indent - 1, { wrap = true })) do
            v:spans(body_indent, nil, line, "ProudText")
          end
        end
      end
    end
  end
  if options.replying then
    v:spans(" " .. string.rep("─", width - 2), "ProudMuted")
    local who = " Reply as " .. (options.viewer and options.viewer ~= "" and options.viewer or "you")
    if width >= #who + 56 then
      v:spans(
        who, "ProudAccentText",
        "  · markdown  · ", "ProudMuted",
        "@", "ProudAccentText",
        " mention  ", "ProudMuted",
        "<C-g>", "ProudAccentText",
        " insert suggestion", "ProudMuted"
      )
    else
      -- Narrow windows: the same hints, shorter.
      v:spans(who, "ProudAccentText", "  · ", "ProudMuted", "@", "ProudAccentText", " mention · ", "ProudMuted", "<C-g>", "ProudAccentText", " suggest", "ProudMuted")
    end
    if options.status then
      for _, line in ipairs(ui.wrap_text(options.status[1], width - 2, { wrap = true })) do
        v:spans(" ", nil, line, options.status[2] or "ProudMuted")
      end
    end
  end
  return v:build(), starts
end

-- Display rows a view takes at `width` (long headers wrap).
local function display_rows(lines, width)
  local rows = 0
  for _, line in ipairs(lines) do
    rows = rows + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
  end
  return rows
end

-- The participants of `threads` and the PR author, for @ completion.
function M.participants(threads, author, viewer)
  local seen, list = {}, {}
  local function add(login)
    if login and login ~= "" and login ~= viewer and login ~= "you" and not seen[login] then
      seen[login] = true
      list[#list + 1] = login
    end
  end
  for _, thread in ipairs(threads) do
    for _, comment in ipairs(thread.comments or {}) do
      add(comment.author)
    end
  end
  add(author)
  return list
end

-- Opens the window. host:
--   window, row      the diff window and the 0-based line the threads are on
--   threads          the threads on that line (mutated on reply/resolve)
--   code             the line's text
--   author           the pull request's author
--   viewer()         the signed-in login, or nil
--   drafts           table of kept drafts by thread id (shared, survives)
--   act(kind, thread, body, done)   kind: "post", "resolve" (post and
--                    resolve), "pending", "resolve_only"; done(ok, result)
--                    with result { comment?, resolved?, pending_count? } or
--                    an error message
--   on_changed(thread, result)      after a successful action
--   on_closed()
-- options.focus focuses it at once. Returns a handle.
function M.open(host, options)
  options = options or {}
  sequence = sequence + 1
  local window = host.window
  local shown = vim.api.nvim_win_get_buf(window)
  local handle = {
    row = host.row,
    shown = shown,
    threads = host.threads,
    closed = false,
  }
  local info = vim.fn.getwininfo(window)[1] or { width = vim.api.nvim_win_get_width(window), textoff = 0 }
  local width = math.max(20, math.min(M.width, info.width - info.textoff - 3))
  handle.width = width

  local buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].filetype = "proud-thread"
  handle.buffer = buffer
  local group = vim.api.nvim_create_augroup("ProudThreadWindow" .. sequence, { clear = true })
  handle.group = group

  -- 0-based screen row of the line inside the diff window.
  local function line_row()
    local position = vim.fn.screenpos(window, host.row + 1, 1)
    if position.row > 0 then
      return position.row - vim.fn.win_screenpos(window)[1]
    end
    return math.max(0, host.row - (vim.fn.line("w0", window) - 1))
  end

  local float, editor
  local starts = {}

  -- Lays out the thread float and, when replying, the editor under it:
  -- below the line when they fit, else above it (editor nearest the line).
  local function layout()
    local window_height = vim.api.nvim_win_get_height(window)
    local screen_row = line_row()
    local below = window_height - screen_row - 1
    local above = screen_row
    local editor_rows = 0
    if editor then
      editor_rows = editor.height + 2
    end
    local content = display_rows(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), width)
    local wanted = content + 2 + editor_rows
    local place_above = below < math.min(wanted, 10 + editor_rows) and above > below
    local room = (place_above and above or below) - editor_rows - 2
    local cap = editor and room or math.min(room, math.floor(window_height * 0.6))
    local height = math.max(1, math.min(content, cap))
    local thread_config = {
      relative = "win",
      win = window,
      bufpos = { host.row, 0 },
      col = 0,
      width = width,
      height = height,
      anchor = place_above and "SW" or "NW",
      row = place_above and -editor_rows or 1,
    }
    if float and vim.api.nvim_win_is_valid(float) then
      vim.api.nvim_win_set_config(float, thread_config)
    else
      float = vim.api.nvim_open_win(buffer, false, vim.tbl_extend("force", thread_config, {
        style = "minimal",
        border = "rounded",
        title = { { #host.threads > 1 and (" %d threads "):format(#host.threads) or " Thread ", "ProudMuted" } },
        title_pos = "left",
        footer = { { " K focus · r reply · R resolve · q close ", "ProudMuted" } },
        footer_pos = "right",
        focusable = true,
        zindex = 60,
      }))
      handle.window = float
      ui.winhighlight(float, { NormalFloat = "ProudCard", FloatBorder = "ProudCardBorder", FloatTitle = "ProudMuted", FloatFooter = "ProudMuted" })
      -- Comments are wrapped already; wrap lets a long header fit.
      vim.wo[float].wrap = true
      vim.wo[float].linebreak = true
      vim.wo[float].cursorline = false
    end
    if editor then
      editor.set_config({
        relative = "win",
        win = window,
        bufpos = { host.row, 0 },
        col = 0,
        anchor = place_above and "SW" or "NW",
        row = place_above and 0 or 1 + height + 2,
      })
    end
  end

  local function render()
    if not vim.api.nvim_buf_is_valid(buffer) then
      return
    end
    local view
    view, starts = M.view(host.threads, width, {
      author = host.author,
      code = host.code,
      replying = editor ~= nil,
      viewer = host.viewer and host.viewer() or nil,
      status = handle.status,
    })
    vim.bo[buffer].modifiable = true
    ui.render(buffer, view)
    vim.bo[buffer].modifiable = false
    layout()
    -- While replying, keep the reply header (and any error) in view when
    -- the thread is taller than the window.
    if editor and float and vim.api.nvim_win_is_valid(float) then
      pcall(vim.api.nvim_win_set_cursor, float, { vim.api.nvim_buf_line_count(buffer), 0 })
    end
  end
  handle.render = render

  -- The thread under the cursor in the window (or the first one).
  local function selected_thread()
    local index = 1
    if float and vim.api.nvim_win_is_valid(float) and vim.api.nvim_get_current_win() == float then
      local cursor = vim.api.nvim_win_get_cursor(float)[1]
      for candidate, start in ipairs(starts) do
        if start <= cursor then
          index = candidate
        end
      end
    end
    return host.threads[index]
  end

  local function save_draft()
    if editor then
      local text = editor.text()
      host.drafts[editor.thread.id or editor.thread] = trim(text) ~= "" and text or nil
    end
  end

  -- Closes the editor; `keep` keeps its text as the thread's draft.
  local function close_editor(keep)
    if not editor then
      return
    end
    local closing = editor
    if keep then
      save_draft()
    else
      host.drafts[closing.thread.id or closing.thread] = nil
    end
    editor = nil
    handle.editor = nil
    handle.status = nil
    if vim.api.nvim_get_current_win() == closing.window and float and vim.api.nvim_win_is_valid(float) then
      vim.cmd("stopinsert")
      vim.api.nvim_set_current_win(float)
    end
    closing.close()
    render()
  end

  function handle.close()
    if handle.closed then
      return
    end
    handle.closed = true
    if editor then
      save_draft()
      local closing = editor
      editor = nil
      closing.close()
    end
    pcall(vim.api.nvim_del_augroup_by_id, group)
    if vim.api.nvim_get_current_win() == float and vim.api.nvim_win_is_valid(window) then
      pcall(vim.api.nvim_set_current_win, window)
    end
    if float and vim.api.nvim_win_is_valid(float) then
      pcall(vim.api.nvim_win_close, float, true)
    end
    if vim.api.nvim_buf_is_valid(buffer) then
      pcall(vim.api.nvim_buf_delete, buffer, { force = true })
    end
    if host.on_closed then
      host.on_closed()
    end
  end

  -- Runs an action against the thread; on success applies its result and
  -- re-renders, on failure shows the error and keeps the draft.
  local function act(kind, thread, body)
    if handle.busy then
      return
    end
    handle.busy = true
    handle.status = { kind == "resolve_only" and "Resolving…" or "Posting…", "ProudMuted" }
    render()
    host.act(kind, thread, body, function(ok, result)
      handle.busy = false
      if handle.closed then
        return
      end
      if not ok then
        local message = type(result) == "table" and (result.message or vim.inspect(result)) or tostring(result or "failed")
        handle.status = { "Could not " .. (kind == "resolve_only" and "resolve" or "post") .. ": " .. message, "ProudDangerText" }
        render()
        vim.notify(handle.status[1], vim.log.levels.ERROR, { title = "proud" })
        return
      end
      result = type(result) == "table" and result or {}
      if result.comment then
        table.insert(thread.comments, result.comment)
      end
      if result.resolved then
        thread.resolved = true
      end
      handle.status = nil
      if editor and editor.thread == thread then
        close_editor(false)
      else
        render()
      end
      if host.on_changed then
        host.on_changed(thread, result)
      end
    end)
  end
  handle.act = act

  local function post(kind)
    if not editor then
      return
    end
    local body = trim(editor.text())
    if body == "" then
      handle.status = { "Write a reply first.", "ProudWarning" }
      render()
      return
    end
    vim.cmd("stopinsert")
    act(kind, editor.thread, body)
  end

  -- Inserts a ```suggestion block with the commented line, cursor inside.
  local function insert_suggestion()
    if not editor then
      return
    end
    local row = vim.api.nvim_win_get_cursor(editor.window)[1]
    local current = vim.api.nvim_buf_get_lines(editor.buffer, row - 1, row, false)[1] or ""
    local block = { "```suggestion", host.code or "", "```" }
    if current == "" then
      vim.api.nvim_buf_set_lines(editor.buffer, row - 1, row, false, block)
      row = row - 1
    else
      vim.api.nvim_buf_set_lines(editor.buffer, row, row, false, block)
    end
    vim.api.nvim_win_set_cursor(editor.window, { row + 2, #(host.code or "") })
  end

  -- Opens the reply editor for `thread` (default: the one under the
  -- cursor), restoring its draft, in Insert mode.
  function handle.reply(thread)
    thread = thread or selected_thread()
    if not thread then
      return
    end
    if editor then
      if editor.thread == thread then
        vim.api.nvim_set_current_win(editor.window)
        return
      end
      close_editor(true)
    end
    handle.status = nil
    local replying = thread
    editor = composer.open({
      config = {
        relative = "win",
        win = window,
        bufpos = { host.row, 0 },
        row = 1,
        col = 0,
        footer = width >= 78 and {
          { " <C-s>", "ProudAccentText" }, { " post  ", "ProudMuted" },
          { "<C-r>", "ProudAccentText" }, { " post and resolve  ", "ProudMuted" },
          { "<C-p>", "ProudAccentText" }, { " add to pending review  ", "ProudMuted" },
          { "<Esc>", "ProudAccentText" }, { " keep draft ", "ProudMuted" },
        } or {
          -- Narrow windows: the same keys, shorter.
          { " <C-s>", "ProudAccentText" }, { " post ", "ProudMuted" },
          { "<C-r>", "ProudAccentText" }, { " +resolve ", "ProudMuted" },
          { "<C-p>", "ProudAccentText" }, { " pending ", "ProudMuted" },
          { "<Esc>", "ProudAccentText" }, { " draft ", "ProudMuted" },
        },
        footer_pos = "left",
      },
      width = width,
      text = host.drafts[thread.id or thread],
      keys = {
        post_reply = function() post("post") end,
        post_and_resolve = function() post("resolve") end,
        add_to_review = function() post("pending") end,
        insert_suggestion = insert_suggestion,
        keep_draft = function()
          vim.cmd("stopinsert")
          close_editor(true)
        end,
      },
      -- @ completes the thread's participants and the PR author.
      mentions = function()
        return M.participants(host.threads, host.author, host.viewer and host.viewer() or nil)
      end,
      on_grow = function()
        layout()
      end,
      -- Closing the editor some other way (:q) keeps the draft.
      on_closed = function()
        if editor and editor.thread == replying then
          close_editor(true)
        end
      end,
    })
    editor.thread = thread
    handle.editor = editor
    render()
  end

  render()

  -- Closes when the cursor leaves the line, on edits, or when the diff
  -- window shows another buffer or closes.
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = shown,
    callback = function()
      if vim.api.nvim_get_current_win() == window and vim.api.nvim_win_get_cursor(window)[1] - 1 ~= host.row then
        handle.close()
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "InsertEnter", "BufWinLeave" }, { group = group, buffer = shown, callback = handle.close })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(window),
    callback = function()
      handle.close()
    end,
  })
  -- Leaving the thread window and its editor for another window closes
  -- it, like LSP hover.
  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = function()
      local left = vim.api.nvim_get_current_win()
      if left ~= float and not (editor and left == editor.window) then
        return
      end
      vim.schedule(function()
        local now = vim.api.nvim_get_current_win()
        if not handle.closed and now ~= float and not (editor and now == editor.window) then
          handle.close()
        end
      end)
    end,
  })
  -- K inside the window has nothing more to show (and must not run
  -- keywordprg on the comment text).
  keymap.map(buffer, "n", "show_thread", function() end, "Already showing the thread")
  keymap.map(buffer, "n", "close_thread", function()
    handle.close()
  end, "Close the thread window")
  keymap.map(buffer, "n", "reply", function()
    handle.reply()
  end, "Reply to the thread")
  keymap.map(buffer, "n", "resolve", function()
    local thread = selected_thread()
    if thread and not thread.resolved then
      act("resolve_only", thread)
    end
  end, "Resolve the thread")

  function handle.focus()
    if float and vim.api.nvim_win_is_valid(float) then
      vim.api.nvim_set_current_win(float)
    end
  end
  if options.focus then
    handle.focus()
  end
  return handle
end

return M
