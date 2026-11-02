local ui = require("proud.ui")
local keymap = require("proud.keymap")
local composer = require("proud.ui.composer")
local sidebar_feature = require("proud.loader").load("sidebar")

local M = {}
local horizontal_padding = 2

local reviewer_state_labels = {
  approved = "approved",
  changes_requested = "changes requested",
  commented = "commented",
  dismissed = "dismissed",
  pending = "review pending",
}

local reviewer_state_highlights = {
  approved = "ProudSuccessText",
  changes_requested = "ProudWarning",
  commented = "ProudMuted",
  dismissed = "ProudMuted",
  pending = "ProudAccentText",
}

local function normalized_files(pull)
  local files = {}
  for _, file in ipairs(pull.files or {}) do
    table.insert(files, {
      path = file.path or file.filename or "",
      status = file.status or "M",
      additions = file.additions or 0,
      deletions = file.deletions or 0,
      threads = file.threads or 0,
      viewed = file.viewed or false,
    })
  end
  return files
end

local function body_lines(body)
  if type(body) == "string" then
    return vim.split(body, "\n", { plain = true })
  end
  if type(body) ~= "table" then
    return {}
  end
  return body
end

local function separator_line(label, width)
  width = math.max(12, math.floor(width or 80))
  local prefix = "── " .. label .. " "
  local prefix_width = ui.display_width(prefix)
  if prefix_width >= width then
    return ui.fit(prefix, width)
  end
  return prefix .. string.rep("─", width - prefix_width)
end

local function conversation_threads(pull)
  local entries = {}
  local seen = {}
  local sequence = 0
  local function collect(value, parent_id, kind)
    if type(value) ~= "table" then
      return
    end
    sequence = sequence + 1
    local source_kind = tostring(value.kind or kind or "comment")
    local source_id = tostring(value.id or ("entry:" .. sequence))
    local id = source_kind .. ":" .. source_id
    if seen[id] then
      return
    end
    seen[id] = true
    table.insert(entries, {
      id = id,
      source_id = source_id,
      source_kind = source_kind,
      reply_to_id = tostring(parent_id or value.reply_to_id or ""),
      reply_to_kind = value.reply_to_kind,
      kind = kind or (source_kind == "review" and "review" or "comment"),
      author = tostring(value.author or value.login or value.name or "unknown"),
      state = tostring(value.state or "commented"):lower():gsub("[%s%-]", "_"),
      age = tostring(value.age or ""),
      body = tostring(value.body or value.message or ""),
    })
    for _, reply in ipairs(value.replies or {}) do
      collect(reply, id, source_kind == "review" and "comment" or kind)
    end
  end
  for _, review in ipairs(pull.reviews or {}) do
    collect(review, nil, "review")
  end
  for _, comment in ipairs(pull.comments or {}) do
    collect(comment, nil, "comment")
  end
  local by_id = {}
  local by_source_id = {}
  for _, entry in ipairs(entries) do
    by_id[entry.id] = entry
    by_source_id[entry.source_id] = by_source_id[entry.source_id] or {}
    table.insert(by_source_id[entry.source_id], entry)
  end
  local children = {}
  local roots = {}
  for _, entry in ipairs(entries) do
    local parent = entry.reply_to_id ~= "" and by_id[entry.reply_to_id] or nil
    if not parent and entry.reply_to_id ~= "" and entry.reply_to_kind then
      parent = by_id[entry.reply_to_kind .. ":" .. entry.reply_to_id]
    end
    if parent == entry then
      parent = nil
    end
    if not parent and entry.reply_to_id ~= "" then
      local candidates = by_source_id[entry.reply_to_id] or {}
      for _, candidate in ipairs(candidates) do
        if candidate ~= entry and (candidate.source_kind == entry.source_kind or candidate.source_kind == "review") then
          parent = candidate
          break
        end
      end
      parent = parent or (candidates[1] ~= entry and candidates[1] or nil)
    end
    if parent then
      children[parent.id] = children[parent.id] or {}
      table.insert(children[parent.id], entry)
    else
      table.insert(roots, entry)
    end
  end
  return roots, children, #entries
end

-- The conversation as cards, in order, plus `entries` by card id with
-- each entry's parent (to find the thread a reply goes to).
local function conversation_items(pull)
  local roots, children, count = conversation_threads(pull)
  local items = {}
  local entries = {}
  local function add(entry, depth, parent)
    entry.parent = parent
    entry.depth = depth
    entries[entry.id] = entry
    local meta_segments
    if entry.kind == "review" then
      meta_segments = {
        { text = "  reviewed", group = "ProudMuted" },
      }
      if entry.state == "changes_requested" then
        table.insert(meta_segments, {
          text = "  change requested",
          group = reviewer_state_highlights.changes_requested,
        })
      elseif entry.state ~= "commented" and entry.state ~= "approved" then
        table.insert(meta_segments, {
          text = "  " .. (reviewer_state_labels[entry.state] or entry.state),
          group = reviewer_state_highlights[entry.state] or "ProudMuted",
        })
      end
    else
      meta_segments = {
        { text = "  commented", group = "ProudMuted" },
      }
    end
    table.insert(items, {
      id = entry.id,
      depth = depth,
      author = entry.author,
      age = entry.age,
      body = entry.body,
      meta_segments = meta_segments,
    })
    for _, reply in ipairs(children[entry.id] or {}) do
      add(reply, depth + 1, entry)
    end
  end
  for _, entry in ipairs(roots) do
    add(entry, 0)
  end
  return items, count, entries
end

-- Inline review comments are threaded on GitHub: a reply goes to the
-- thread's first comment. Everything else (the description, reviews, PR
-- comments) is answered with a quote in a new PR comment, like GitHub's
-- "Quote reply".
function M.thread_root(entry)
  if not entry or entry.source_kind ~= "review_comment" then
    return nil
  end
  while entry.parent and entry.parent.source_kind == "review_comment" do
    entry = entry.parent
  end
  return entry
end

function M.quote(author, body)
  local lines = {}
  for _, line in ipairs(vim.split(tostring(body or ""), "\n", { plain = true })) do
    lines[#lines + 1] = line == "" and ">" or ("> " .. line)
  end
  if author and author ~= "" then
    table.insert(lines, 1, "> @" .. author .. " wrote:")
    table.insert(lines, 2, ">")
  end
  return table.concat(lines, "\n") .. "\n\n"
end

-- Logins offered after "@": the PR author and everyone in the conversation.
function M.participants(state)
  local seen, names = {}, {}
  local function add(login)
    if login and login ~= "" and login ~= "unknown" and not seen[login] then
      seen[login] = true
      names[#names + 1] = login
    end
  end
  add(state.pull.author)
  for _, review in ipairs(state.pull.reviews or {}) do
    add(review.author)
  end
  for _, comment in ipairs(state.pull.comments or {}) do
    add(comment.author)
  end
  for _, reviewer in ipairs(state.pull.reviewers or {}) do
    add(reviewer.login)
  end
  return names
end

local composer_header = {
  { text = "Comment", group = "ProudAccentText" },
  { text = "  · markdown · ", group = "ProudMuted" },
  { text = "<C-s>", group = "ProudAccentText" },
  { text = " post · ", group = "ProudMuted" },
  { text = "<Esc>", group = "ProudAccentText" },
  { text = " draft", group = "ProudMuted" },
}

-- Adds the comment box (or, while writing, the editor's slot) to `items`.
local function with_composer(state, items, entries)
  local composing = state.composing
  local result = items
  if composing and composing.target ~= "new" then
    -- A reply: room for the editor at the end of its thread.
    local root = entries[composing.target]
    if root then
      result = {}
      local inside, placed = false, false
      for _, item in ipairs(items) do
        local entry = entries[item.id]
        if inside and not placed and (not entry or entry.depth <= root.depth) then
          result[#result + 1] = { id = "composer", slot = true, depth = root.depth + 1, height = composing.height }
          placed = true
        end
        if item.id == root.id then
          inside = true
        end
        result[#result + 1] = item
      end
      if not placed then
        result[#result + 1] = { id = "composer", slot = true, depth = root.depth + 1, height = composing.height }
      end
    end
  end
  if composing and composing.target == "new" then
    result[#result + 1] = { id = "composer", slot = true, depth = 0, height = composing.height }
  else
    local draft = state.drafts and state.drafts.new
    result[#result + 1] = {
      id = "comment_box",
      depth = 0,
      header_segments = composer_header,
      body = draft or "Leave a comment on the PR",
      body_group = draft and "ProudText" or "ProudMuted",
      border_group = "ProudCardBorderSelected",
    }
  end
  return result
end

function M.hydrate(state, pull, options)
  options = options or {}
  pull = require("proud.provider").normalize_pull_request(pull)
  local tree = require("proud.components.tree")
  local layout = state.sidebar and tree.layout(state.sidebar) or {}
  state.pull = pull
  state.body = body_lines(pull.body)
  state.files = normalized_files(pull)
  state.commits = pull.commits or {}
  state.checks = pull.checks or {}
  if not options.keep_loading then
    state.loading = false
  end
  local next_sidebar = sidebar_feature.create(sidebar_feature.overview_nodes(state), {
    selected_id = layout.selected_id
      or (state.files[1] and ("file:" .. state.files[1].path))
      or "files",
  })
  if state.sidebar then
    state.sidebar.roots = next_sidebar.roots
    state.sidebar.selected_id = next_sidebar.selected_id
    tree.restore_layout(state.sidebar, layout)
  else
    state.sidebar = next_sidebar
    tree.restore_layout(state.sidebar, layout)
  end
  if state.refresh then
    state.refresh()
  end
  return state
end

function M.create(pull, options)
  options = options or {}
  local normalized = require("proud.provider").normalize_pull_request(pull)
  local state = {
    pull = normalized,
    body = body_lines(normalized.body),
    files = normalized_files(normalized),
    commits = normalized.commits or {},
    checks = normalized.checks or {},
    loading = options.loading == true,
  }
  state.sidebar = sidebar_feature.create(sidebar_feature.overview_nodes(state), {
    selected_id = state.files[1] and ("file:" .. state.files[1].path) or "files",
  })
  return M.hydrate(state, pull, { keep_loading = options.loading == true })
end

function M.viewed_count(state)
  local count = 0
  for _, file in ipairs(state.files) do
    if file.viewed then
      count = count + 1
    end
  end
  return count
end

function M.mark_viewed(state, path)
  for _, file in ipairs(state.files) do
    if file.path == path then
      file.viewed = true
      local node = sidebar_feature.components.tree.find(state.sidebar, "file:" .. path)
      if node then
        node.payload.file = file
        local replacement_nodes = sidebar_feature.overview_nodes(state)
        local function find_file(nodes)
          for _, item in ipairs(nodes or {}) do
            if item.id == "file:" .. path then
              return item
            end
            local found = find_file(item.children)
            if found then
              return found
            end
          end
        end
        local replacement
        for _, root in ipairs(replacement_nodes) do
          replacement = replacement or find_file(root.children)
        end
        if replacement then
          node.sections = sidebar_feature.components.section_row.normalize_sections(replacement.sections)
        end
      end
      return true
    end
  end
  return false
end

function M.render(state, width)
  width = math.max(36, math.floor(width or 80))
  local inner_width = math.max(1, width - horizontal_padding * 2)
  local pull = state.pull
  local box = { width = width, padding = horizontal_padding }
  local v = ui.view.new()
  local function line(...)
    return v:wrapped({ ... }, box)
  end

  local review_summary = {}
  for _, reviewer in ipairs(pull.reviewers or {}) do
    local state_label = reviewer_state_labels[reviewer.state] or reviewer.state or "review pending"
    table.insert(review_summary, tostring(reviewer.login or reviewer.name or "unknown") .. " " .. state_label)
  end
  local label_text = table.concat(pull.labels or {}, " · ")

  line({ pull.title, "ProudBright" }, "  ", { "#" .. tostring(pull.number), "ProudAccentText" })
  line(
    "● ", { pull.state or "Open", "ProudSuccessText" }, "    ",
    { pull.author or "unknown", "ProudAccentText" }
  )
  line(
    "  wants to merge into ", { pull.base_ref or "main", "ProudAccentText" },
    " from ", { pull.head_ref or "", "ProudAccentText" }
  )
  line({ "Reviewers", "ProudMuted" }, "  " .. (#review_summary > 0 and table.concat(review_summary, "   ") or "none"))
  line({ "Labels", "ProudMuted" }, "     ", label_text ~= "" and { label_text, "ProudAccentText" } or "none")
  line({ "Milestone", "ProudMuted" }, "  " .. (pull.milestone or "none"))
  line("")
  local description_first = v:row() + 1
  line({ separator_line("Description", inner_width), "ProudMuted" })
  for _, source in ipairs(state.body) do
    if source:match("^## ") then
      line({ source, "ProudAccentText" })
    elseif source:match("^%- %[x%]") then
      line({ "- [x]", "ProudSuccessText" }, source:sub(6))
    elseif source:match("^%- %[ %]") then
      line({ "- [ ]", "ProudWarning" }, source:sub(6))
    else
      line(source)
    end
  end
  if state.loading and #state.body == 0 then
    line("Loading pull request details...")
  end
  -- Places the cursor can jump to: the description, then each card.
  local items = {
    { id = "description", first = description_first, last = math.max(description_first, v:row()) },
  }
  line("")

  local card_items, conversation_count, entries = conversation_items(pull)
  state.entries = entries
  line({ separator_line("Conversation " .. conversation_count, inner_width), "ProudMuted" })
  local conversation_cards = require("proud.loader").load("conversation_cards")
  if #card_items == 0 then
    line({ "No conversation yet", "ProudMuted" })
  end
  line("")
  local specs = conversation_cards.layout(with_composer(state, card_items, entries), {
    width = math.max(12, width - horizontal_padding * 2 - 2),
    margin = 0,
    min_width = 12,
    col_offset = horizontal_padding,
    start_row = v:row() + 1,
    gap = 1,
  })
  for _ = 1, specs.total_rows do
    line("")
  end
  state.conversation_cards = specs
  for _, spec in ipairs(specs) do
    items[#items + 1] = { id = spec.id, first = spec.row, last = spec.row + spec.height + 1, spec = spec }
  end
  line("")

  local view = v:build()
  view.conversation_cards = state.conversation_cards
  view.items = items
  view.padding = horizontal_padding
  state.items = items
  return view
end

-- The navigation item (description, card, comment box) at 1-based `line`.
function M.item_at(state, line)
  for _, item in ipairs(state.items or {}) do
    if line >= item.first and line <= item.last then
      return item
    end
  end
  return nil
end

-- The item after (direction 1) or before (-1) the one at `line`.
function M.step_item(state, line, direction)
  local items = {}
  for _, item in ipairs(state.items or {}) do
    if not (item.spec and item.spec.slot) then
      items[#items + 1] = item
    end
  end
  if direction > 0 then
    for _, item in ipairs(items) do
      if item.first > line then
        return item
      end
    end
  else
    for index = #items, 1, -1 do
      if items[index].last < line then
        return items[index]
      end
    end
  end
  return nil
end

-- The 1-based line the cursor rests on for `item`: a card's header, the
-- description's first line.
local function item_line(item)
  if item.spec then
    return item.spec.row + 1
  end
  return item.first
end

-- Adds a posted comment to the conversation so it shows at once.
function M.add_comment(state, comment, reply_to)
  state.pull.comments = state.pull.comments or {}
  table.insert(state.pull.comments, {
    id = tostring(comment.id or ("local:" .. (#state.pull.comments + 1))),
    kind = reply_to and "review_comment" or "comment",
    reply_to_id = reply_to and reply_to.source_id or nil,
    reply_to_kind = reply_to and "review_comment" or nil,
    author = comment.author or "you",
    age = comment.age or "now",
    body = comment.body or "",
  })
  return "" .. (reply_to and "review_comment:" or "comment:") .. tostring(state.pull.comments[#state.pull.comments].id)
end

function M.render_panes(state, options)
  options = options or {}
  return {
    sidebar = sidebar_feature.render(state.sidebar, options.sidebar_width or 44),
    details = M.render(state, options.details_width or 80),
  }
end

function M.attach(buffer, state, options)
  options = options or {}
  local workspace = options.workspace
  local sidebar_buffer = ui.workspace_buffer(workspace, "sidebar")
  -- The sidebar can be hidden and shown again (a new window), so look it
  -- up each time.
  local function sidebar_window()
    return ui.workspace_window(workspace, "sidebar")
  end
  local details_buffer = ui.workspace_buffer(workspace, "details")
  local details_window = ui.workspace_window(workspace, "details")
  local conversation_cards = require("proud.loader").load("conversation_cards")
  if state.comment_card_windows then
    conversation_cards.close(state.comment_card_windows)
  end
  state.comment_card_windows = conversation_cards.create({ host_window = details_window })

  state.drafts = state.drafts or {}
  local card_group = vim.api.nvim_create_augroup("ProudOverviewConversation" .. details_buffer, { clear = true })

  local function current_path()
    local selected = sidebar_feature.selected_file(state.sidebar)
    return selected and selected.path
      or options.current_path
      or (state.files[1] and state.files[1].path)
  end

  local function refresh()
    local window = sidebar_window()
    local sidebar_width = window and vim.api.nvim_win_get_width(window) or 44
    local details_width = vim.api.nvim_win_is_valid(details_window)
      and vim.api.nvim_win_get_width(details_window)
      or 80
    local panes = M.render_panes(state, {
      sidebar_width = sidebar_width,
      details_width = details_width,
    })
    ui.render_workspace(workspace, panes)
    conversation_cards.sync(state.comment_card_windows, panes.details.conversation_cards)
    sidebar_feature.sync_cursor(state.sidebar, sidebar_window())
    if state.place_editor then
      state.place_editor()
    end
  end
  state.refresh = refresh

  -- The card under the cursor gets an accent border.
  local function sync_focus()
    if not vim.api.nvim_win_is_valid(details_window) then
      return
    end
    local item = M.item_at(state, vim.api.nvim_win_get_cursor(details_window)[1])
    local id = item and item.spec and not item.spec.slot and item.id or nil
    state.focused = item and item.id or nil
    if state.comment_card_windows.selected_id ~= id then
      conversation_cards.select(state.comment_card_windows, id)
    end
  end
  vim.api.nvim_create_autocmd("CursorMoved", { group = card_group, buffer = details_buffer, callback = sync_focus })

  -- Moves the cursor to `item`, scrolling so the whole card shows.
  local function go_to(item)
    if not item or not vim.api.nvim_win_is_valid(details_window) then
      return
    end
    vim.api.nvim_win_set_cursor(details_window, { item_line(item), 0 })
    vim.api.nvim_win_call(details_window, function()
      local view = vim.fn.winsaveview()
      local height = vim.api.nvim_win_get_height(details_window)
      if item.last > view.topline + height - 1 then
        view.topline = math.max(1, math.min(item.first, item.last - height + 1))
        vim.fn.winrestview(view)
      end
    end)
    sync_focus()
  end
  state.go_to = go_to

  -- The editor for a new comment or a reply, in its slot in the
  -- conversation; it follows scrolling.
  local editor
  local function slot()
    for _, spec in ipairs(state.conversation_cards or {}) do
      if spec.slot then
        return spec
      end
    end
  end
  local function placement()
    local spec = slot()
    if not spec or not vim.api.nvim_win_is_valid(details_window) then
      return nil
    end
    local topline = vim.api.nvim_win_call(details_window, function()
      return vim.fn.winsaveview().topline
    end)
    local top = spec.row - topline
    return {
      relative = "win",
      win = details_window,
      row = top,
      col = spec.col,
      hide = top < 0 or top >= vim.api.nvim_win_get_height(details_window),
    }
  end
  function state.place_editor()
    local config = editor and placement()
    if config then
      editor.set_config(config)
    end
  end
  vim.api.nvim_create_autocmd({ "WinScrolled", "WinResized" }, {
    group = card_group,
    callback = function()
      vim.schedule(function()
        if state.place_editor then
          state.place_editor()
        end
      end)
    end,
  })

  local function draft_key(target)
    return target == "new" and "new" or ("reply:" .. target)
  end

  local function close_editor(keep, focus_id)
    if not editor then
      return
    end
    local closing = editor
    editor = nil
    local text = closing.text()
    state.drafts[draft_key(closing.target)] = keep and composer.trim(text) ~= "" and text or nil
    closing.close()
    state.composing = nil
    refresh()
    if vim.api.nvim_win_is_valid(details_window) then
      vim.api.nvim_set_current_win(details_window)
      local wanted = focus_id or (closing.target == "new" and "comment_box" or closing.target)
      for _, item in ipairs(state.items or {}) do
        if item.id == wanted then
          go_to(item)
          break
        end
      end
    end
  end
  state.close_editor = close_editor

  local function set_status(text, group)
    if editor and vim.api.nvim_win_is_valid(editor.window) then
      local config = vim.api.nvim_win_get_config(editor.window)
      config.footer = { { " " .. text .. " ", group } }
      config.footer_pos = "left"
      vim.api.nvim_win_set_config(editor.window, config)
    end
  end

  local function post()
    if not editor or editor.busy then
      return
    end
    local body = composer.trim(editor.text())
    if body == "" then
      set_status("Write something first.", "ProudWarning")
      return
    end
    vim.cmd("stopinsert")
    local posting = editor
    posting.busy = true
    set_status("Posting…", "ProudMuted")
    local root = posting.target ~= "new" and state.entries and state.entries[posting.target] or nil
    local kind = root and "reply" or "comment"
    local act = options.on_comment or function(_, _, text, done)
      vim.schedule(function()
        done(true, { author = options.viewer and options.viewer() or "you", body = text })
      end)
    end
    act(kind, root, body, function(ok, result)
      posting.busy = false
      if editor ~= posting then
        return
      end
      if not ok then
        local message = type(result) == "table" and (result.message or vim.inspect(result)) or tostring(result or "failed")
        set_status("Could not post: " .. message, "ProudDangerText")
        vim.notify("Could not post: " .. message, vim.log.levels.ERROR, { title = "proud" })
        return
      end
      result = type(result) == "table" and result or {}
      result.body = result.body or body
      result.author = result.author or (options.viewer and options.viewer()) or "you"
      local id = M.add_comment(state, result, root)
      close_editor(false, id)
    end)
  end

  -- Opens the editor: target "new" (a PR comment) or a thread root's id.
  local function open_editor(target, text)
    if editor then
      if editor.target == target and not text then
        vim.api.nvim_set_current_win(editor.window)
        vim.cmd("startinsert!")
        return
      end
      close_editor(true)
    end
    local draft = state.drafts[draft_key(target)]
    if text then
      draft = (draft and draft ~= "" and (draft .. "\n\n") or "") .. text
    end
    -- The slot's width is known only after layout: size it for the
    -- narrowest card (a reply's); the editor corrects it as it grows.
    local width = vim.api.nvim_win_get_width(details_window) - horizontal_padding * 2 - 6
    state.composing = { target = target, height = composer.rows(draft, width) }
    refresh()
    local spec = slot()
    if not spec then
      state.composing = nil
      refresh()
      return
    end
    go_to({ first = spec.row, last = spec.row + spec.height + 1 })
    local root = target ~= "new" and state.entries[target] or nil
    local title = root
      and { { " Reply to " .. root.author, "ProudAccentText" }, { " · markdown · @ mention ", "ProudMuted" } }
      or { { " Comment", "ProudAccentText" }, { " · markdown · @ mention ", "ProudMuted" } }
    editor = composer.open({
      config = vim.tbl_extend("force", placement(), {
        title = title,
        title_pos = "left",
        footer = {
          { " <C-s>", "ProudAccentText" }, { " post  ", "ProudMuted" },
          { "<Esc>", "ProudAccentText" }, { " keep draft ", "ProudMuted" },
        },
        footer_pos = "left",
      }),
      width = spec.width,
      text = draft,
      highlight = {
        NormalFloat = "ProudBackground",
        FloatBorder = "ProudCardBorderSelected",
        FloatTitle = "ProudAccentText",
        FloatFooter = "ProudMuted",
      },
      keys = {
        post_reply = post,
        keep_draft = function()
          close_editor(true)
        end,
      },
      mentions = function()
        return M.participants(state)
      end,
      on_grow = function(height)
        if state.composing then
          state.composing.height = height
          refresh()
        end
      end,
      on_closed = function()
        if editor then
          close_editor(true)
        end
      end,
    })
    editor.target = target
    state.editor = editor
    if state.composing.height ~= editor.height then
      state.composing.height = editor.height
      refresh()
    end
    state.place_editor()
  end
  state.open_editor = open_editor
  vim.api.nvim_create_autocmd("WinClosed", {
    group = card_group,
    pattern = tostring(details_window),
    callback = function()
      if editor then
        local closing = editor
        editor = nil
        local text = closing.text()
        state.drafts[draft_key(closing.target)] = composer.trim(text) ~= "" and text or nil
        closing.close()
        state.composing = nil
      end
      pcall(vim.api.nvim_del_augroup_by_id, card_group)
    end,
  })

  -- r: reply to the item under the cursor. Inline review comments get a
  -- threaded reply; anything else is quoted into a new PR comment.
  local function reply()
    local item = M.item_at(state, vim.api.nvim_win_get_cursor(details_window)[1])
    if not item or item.id == "comment_box" then
      open_editor("new")
      return
    end
    if item.id == "description" then
      open_editor("new", M.quote(state.pull.author, table.concat(state.body, "\n")))
      return
    end
    local entry = state.entries and state.entries[item.id]
    if not entry then
      return
    end
    local root = M.thread_root(entry)
    if root then
      open_editor(root.id)
    else
      open_editor("new", M.quote(entry.author, entry.body))
    end
  end

  sidebar_feature.attach(sidebar_buffer, state.sidebar, {
    get_window = sidebar_window,
    refresh = refresh,
    on_open = function(file)
      if options.on_diff then
        options.on_diff(file.path)
      end
    end,
    -- A commit opens the diff page on that commit's change.
    on_activate = function(node)
      if node.kind == "commit" and node.payload and options.on_commit then
        options.on_commit(node.payload.sha)
      end
    end,
    on_toggle_viewed = function(path)
      M.mark_viewed(state, path)
    end,
  })

  keymap.map(details_buffer, "n", "toggle_viewed", function()
    local path = current_path()
    if path and M.mark_viewed(state, path) then
      refresh()
    end
  end, "Mark current file viewed")
  keymap.map(details_buffer, "n", "open_diff", function()
    if state.focused == "comment_box" then
      open_editor("new")
    elseif options.on_diff then
      options.on_diff(current_path())
    end
  end, "Open full-file diff")
  keymap.map(details_buffer, "n", "next_conversation_item", function()
    go_to(M.step_item(state, vim.api.nvim_win_get_cursor(details_window)[1], 1))
  end)
  keymap.map(details_buffer, "n", "previous_conversation_item", function()
    go_to(M.step_item(state, vim.api.nvim_win_get_cursor(details_window)[1], -1))
  end)
  keymap.map(details_buffer, "n", "reply", reply, "Reply to the comment under the cursor")
  keymap.map_workspace(workspace, "n", "toggle_sidebar", function()
    if ui.toggle_pane(workspace, "sidebar") then
      refresh()
    end
  end, "Show or hide the sidebar")
  local open_review = options.on_review or options.on_comment or function() end
  keymap.map_workspace(workspace, "n", "open_review", open_review, "Compose pull request review")
  keymap.map(details_buffer, "n", "comment", function()
    open_editor("new")
  end, "Comment on the pull request")
  keymap.bind_common_workspace(workspace, {
    on_quit = options.on_quit or function()
      ui.close_workspace(workspace)
    end,
  })
  refresh()
end

function M.open(state, options)
  options = options or {}
  local name = "proud://pr/" .. tostring(state.pull.number) .. "/overview"
  if options.current_path then
    sidebar_feature.select_file(state.sidebar, options.current_path)
  end
  local panes = M.render_panes(state, {
    details_width = math.max(36, math.floor(vim.o.columns * 0.60)),
  })
  local workspace = ui.open_workspace(name, {
    {
      name = "sidebar",
      buffer_name = name .. "/sidebar",
      title = "#" .. tostring(state.pull.number) .. " overview",
      view = panes.sidebar,
      weight = 0.40,
    },
    {
      name = "details",
      buffer_name = name .. "/details",
      title = "#" .. tostring(state.pull.number) .. " overview",
      view = panes.details,
      weight = 0.60,
    },
  }, {
    focus = "sidebar",
    title = "#" .. tostring(state.pull.number) .. " overview",
    statusline = "#" .. tostring(state.pull.number) .. " overview",
    on_resize = function()
      if state.refresh then
        state.refresh()
      end
    end,
  })
  state.workspace = workspace
  local buffer = ui.workspace_buffer(workspace, "sidebar")
  M.attach(buffer, state, vim.tbl_extend("force", options, { workspace = workspace }))
  return buffer
end

return M
