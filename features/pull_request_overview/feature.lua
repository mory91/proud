local ui = require("proud.ui")
local keymap = require("proud.keymap")
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

local add_span = ui.view.span

local function find_line(lines, needle)
  for index, line in ipairs(lines) do
    if line:find(needle, 1, true) then
      return index - 1
    end
  end
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

local function content_lines(value, width, padding)
  return ui.content_lines(value, {
    width = width,
    padding = padding or horizontal_padding,
  })
end

local function content_line(value, width, padding)
  local lines = content_lines(value, width, padding)
  return lines[1] or ""
end

local function content_spans(lines, highlights, value, start_line, group, needle, whole_line)
  local offset = 0
  for _, source in ipairs(vim.split(tostring(value or ""), "\n", { plain = true })) do
    if source ~= "" then
      local found = add_span(lines, highlights, start_line + offset, needle or source, group)
      if not found and whole_line then
        local rendered = lines[start_line + offset + 1] or ""
        local text = rendered
          :sub(horizontal_padding + 1, math.max(horizontal_padding, #rendered - horizontal_padding))
          :gsub("%s+$", "")
        add_span(lines, highlights, start_line + offset, text, group)
      end
    end
    offset = offset + 1
  end
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

local function conversation_items(pull)
  local roots, children, count = conversation_threads(pull)
  local items = {}
  local function add(entry, depth)
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
      add(reply, depth + 1)
    end
  end
  for _, entry in ipairs(roots) do
    add(entry, 0)
  end
  return items, count
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
  local reviewer_values = pull.reviewers or {}
  local review_summary = {}
  for _, reviewer in ipairs(reviewer_values) do
    local state_label = reviewer_state_labels[reviewer.state] or reviewer.state or "review pending"
    table.insert(review_summary, tostring(reviewer.login or reviewer.name or "unknown") .. " " .. state_label)
  end
  local title = pull.title .. "  #" .. tostring(pull.number)
  local summary = "● " .. (pull.state or "Open") .. "    " .. (pull.author or "unknown")
  local merge = "  wants to merge into " .. (pull.base_ref or "main") .. " from " .. (pull.head_ref or "")
  local reviewers = "Reviewers  " .. (#review_summary > 0 and table.concat(review_summary, "   ") or "none")
  local labels = "Labels     " .. (#(pull.labels or {}) > 0 and table.concat(pull.labels, " · ") or "none")
  local milestone = "Milestone  " .. (pull.milestone or "none")
  local title_lines = content_lines(title, width, horizontal_padding)
  local summary_lines = content_lines(summary, width, horizontal_padding)
  local merge_lines = content_lines(merge, width, horizontal_padding)
  local reviewer_lines = content_lines(reviewers, width, horizontal_padding)
  local label_lines = content_lines(labels, width, horizontal_padding)
  local milestone_lines = content_lines(milestone, width, horizontal_padding)
  local lines = {}
  for _, group in ipairs({ title_lines, summary_lines, merge_lines, reviewer_lines, label_lines, milestone_lines }) do
    vim.list_extend(lines, group)
  end
  table.insert(lines, content_line("", width, horizontal_padding))
  table.insert(lines, content_line(separator_line("Description", inner_width), width, horizontal_padding))
  local body_start = #lines
  for _, line in ipairs(state.body) do
    vim.list_extend(lines, content_lines(line, width, horizontal_padding))
  end
  if state.loading and #state.body == 0 then
    table.insert(lines, content_line("Loading pull request details...", width, horizontal_padding))
  end
  table.insert(lines, content_line("", width, horizontal_padding))

  local highlights = {}
  local summary_start = #title_lines
  local merge_start = summary_start + #summary_lines
  local reviewer_start = merge_start + #merge_lines
  local label_start = reviewer_start + #reviewer_lines
  local milestone_start = label_start + #label_lines
  content_spans(lines, highlights, pull.title, 0, "ProudBright", pull.title, true)
  add_span(lines, highlights, 0, "#" .. tostring(pull.number), "ProudAccentText")
  content_spans(lines, highlights, pull.state or "Open", summary_start, "ProudSuccessText", pull.state or "Open")
  content_spans(lines, highlights, pull.author or "unknown", summary_start, "ProudAccentText", pull.author or "unknown")
  content_spans(lines, highlights, pull.base_ref or "main", merge_start, "ProudAccentText", pull.base_ref or "main")
  content_spans(lines, highlights, pull.head_ref or "", merge_start, "ProudAccentText", pull.head_ref or "")
  content_spans(lines, highlights, "Reviewers", reviewer_start, "ProudMuted", "Reviewers")
  content_spans(lines, highlights, "Labels", label_start, "ProudMuted", "Labels")
  content_spans(lines, highlights, table.concat(pull.labels or {}, " · "), label_start, "ProudAccentText", table.concat(pull.labels or {}, " · "))
  content_spans(lines, highlights, "Milestone", milestone_start, "ProudMuted", "Milestone")
  content_spans(lines, highlights, separator_line("Description", inner_width), milestone_start + #milestone_lines + 1, "ProudMuted", separator_line("Description", inner_width))
  local body_line = body_start
  for _, source in ipairs(state.body) do
    local wrapped = content_lines(source, width, horizontal_padding)
    for _, line in ipairs(wrapped) do
      local text = line
        :sub(horizontal_padding + 1, math.max(horizontal_padding, #line - horizontal_padding))
        :gsub("%s+$", "")
      if source:match("^## ") then
        add_span(lines, highlights, body_line, text, "ProudAccentText")
      elseif source:match("^%- %[x%]") then
        add_span(lines, highlights, body_line, "- [x]", "ProudSuccessText")
      elseif source:match("^%- %[ %]") then
        add_span(lines, highlights, body_line, "- [ ]", "ProudWarning")
      end
      body_line = body_line + 1
    end
  end

  local card_items, conversation_count = conversation_items(pull)
  table.insert(lines, content_line(separator_line("Conversation " .. conversation_count, inner_width), width, horizontal_padding))
  local conversation_row = #lines - 1
  add_span(lines, highlights, conversation_row, lines[conversation_row + 1], "ProudMuted")

  local conversation_cards = require("proud.loader").load("conversation_cards")
  if #card_items == 0 then
    table.insert(lines, content_line("No conversation yet", width, horizontal_padding))
    add_span(lines, highlights, #lines - 1, "No conversation yet", "ProudMuted")
    state.conversation_cards = {}
  else
    table.insert(lines, content_line("", width, horizontal_padding))
    local specs = conversation_cards.layout(card_items, {
      width = math.max(12, width - horizontal_padding * 2 - 2),
      margin = 0,
      min_width = 12,
      col_offset = horizontal_padding,
      start_row = #lines + 1,
      gap = 1,
    })
    for _ = 1, specs.total_rows do
      table.insert(lines, content_line("", width, horizontal_padding))
    end
    state.conversation_cards = specs
  end
  table.insert(lines, content_line("", width, horizontal_padding))
  table.insert(lines, content_line("Comment  draft", width, horizontal_padding))

  local comment_row = find_line(lines, "Comment  draft")
  if comment_row then
    add_span(lines, highlights, comment_row, "Comment", "ProudMuted")
    add_span(lines, highlights, comment_row, "draft", "ProudAccentText")
  end
  return {
    lines = lines,
    highlights = highlights,
    conversation_cards = state.conversation_cards,
    padding = horizontal_padding,
  }
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
  local sidebar_window = ui.workspace_window(workspace, "sidebar")
  local details_buffer = ui.workspace_buffer(workspace, "details")
  local details_window = ui.workspace_window(workspace, "details")
  local conversation_cards = require("proud.loader").load("conversation_cards")
  if state.comment_card_windows then
    conversation_cards.close(state.comment_card_windows)
  end
  state.comment_card_windows = conversation_cards.create({ host_window = details_window })

  local function current_path()
    local selected = sidebar_feature.selected_file(state.sidebar)
    return selected and selected.path
      or options.current_path
      or (state.files[1] and state.files[1].path)
  end

  local function refresh()
    local sidebar_width = vim.api.nvim_win_is_valid(sidebar_window)
      and vim.api.nvim_win_get_width(sidebar_window)
      or 44
    local details_width = vim.api.nvim_win_is_valid(details_window)
      and vim.api.nvim_win_get_width(details_window)
      or 80
    local panes = M.render_panes(state, {
      sidebar_width = sidebar_width,
      details_width = details_width,
    })
    ui.render_workspace(workspace, panes)
    conversation_cards.sync(state.comment_card_windows, panes.details.conversation_cards)
    sidebar_feature.sync_cursor(state.sidebar, sidebar_window)
  end
  state.refresh = refresh

  sidebar_feature.attach(sidebar_buffer, state.sidebar, {
    window = sidebar_window,
    refresh = refresh,
    on_open = function(file)
      if options.on_diff then
        options.on_diff(file.path)
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
    if options.on_diff then
      options.on_diff(current_path())
    end
  end, "Open full-file diff")
  local open_review = options.on_review or options.on_comment or function() end
  keymap.map_workspace(workspace, "n", "open_review", open_review, "Compose pull request review")
  keymap.map(details_buffer, "n", "comment", open_review, "Compose pull request review")
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
