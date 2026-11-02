local ui = require("proud.ui")
local keymap = require("proud.keymap")
local section_row = require("proud.components.section_row")
local tree_component = require("proud.components.tree")

local M = {
  components = {
    section_row = section_row,
    tree = tree_component,
  },
}

local function file_sections(file)
  local sections = {
    {
      text = vim.fn.fnamemodify(file.path or file.filename or "", ":t"),
      group = "ProudBright",
    },
    {
      parts = {
        { text = "+" .. tostring(file.additions or 0), group = "ProudSuccessText" },
        { text = "-" .. tostring(file.deletions or 0), group = "ProudDangerText" },
      },
    },
  }
  if (file.threads or 0) > 0 then
    table.insert(sections, {
      text = "◆" .. tostring(file.threads),
      group = "ProudWarning",
    })
  end
  if file.viewed then
    table.insert(sections, {
      text = "viewed",
      group = "ProudSuccessText",
    })
  end
  return sections
end

local function root_node(id, label, summary, children)
  return {
    id = id,
    kind = "header",
    label = label,
    expanded = true,
    spacing = 1,
    sections = section_row.normalize_sections({
      { text = label, group = "ProudBright" },
      { text = tostring(summary), group = "ProudMuted" },
    }),
    children = children,
  }
end

local function loading_children(state, id, label)
  if not state.loading then
    return {}
  end
  return {
    {
      id = "loading:" .. id,
      kind = "loading",
      label = "Loading " .. label,
      marker = "",
      sections = { { text = "Loading " .. label .. "...", group = "ProudMuted" } },
    },
  }
end

local function files_summary(total, viewed)
  return ("%d · %d of %d viewed"):format(total, viewed, total)
end

local function checks_summary(checks)
  local passing = 0
  for _, check in ipairs(checks or {}) do
    if check.status == "pass" then
      passing = passing + 1
    end
  end
  return ("%d of %d passing"):format(passing, #(checks or {}))
end

local function check_sections(check)
  local symbol = check.status == "pass" and "✓" or check.status == "pending" and "○" or "✗"
  local group = check.status == "pass" and "ProudSuccessText"
    or check.status == "pending" and "ProudWarning"
    or "ProudDangerText"
  local name = tostring(check.name or "")
  local name_width = 18
  local padding = string.rep(" ", math.max(0, name_width - ui.display_width(name)))
  local sections = {
    { text = symbol, group = group },
    {
      parts = {
        { text = name, group = "ProudBright" },
        { text = padding },
      },
    },
  }
  local duration = tostring(check.duration or "")
  if duration ~= "" then
    table.insert(sections, { text = duration, group = "ProudMuted" })
  end
  return sections
end

local function refresh_file_status(state)
  for _, root in ipairs(state.roots or {}) do
    if root.id == "files" then
      local total = 0
      local viewed = 0
      local function count(nodes)
        for _, node in ipairs(nodes or {}) do
          if node.kind == "file" then
            total = total + 1
            local viewed_value = node.payload
              and (node.payload.file and node.payload.file.viewed or node.payload.viewed)
            if viewed_value then
              viewed = viewed + 1
            end
          end
          count(node.children)
        end
      end
      count(root.children)
      root.sections = section_row.normalize_sections({
        { text = "Files", group = "ProudBright" },
        {
          text = files_summary(total, viewed),
          group = "ProudMuted",
        },
      })
    end
  end
end

function M.overview_nodes(state)
  local viewed = 0
  local directories = {}
  local directory_order = {}
  for _, file in ipairs(state.files or {}) do
    if file.viewed then
      viewed = viewed + 1
    end
    local path = file.path or file.filename or ""
    local directory = vim.fn.fnamemodify(path, ":h")
    if directory == "." then
      directory = "root"
    end
    if not directories[directory] then
      directories[directory] = {}
      table.insert(directory_order, directory)
    end
    table.insert(directories[directory], {
      id = "file:" .. path,
      kind = "file",
      label = vim.fn.fnamemodify(path, ":t"),
      spacing = { 2, 2, 2 },
      sections = file_sections(file),
      payload = {
        path = path,
        file = file,
        viewed = file.viewed or false,
      },
    })
  end

  local file_children = {}
  for _, directory in ipairs(directory_order) do
    table.insert(file_children, {
      id = "path:" .. directory,
      kind = "path",
      label = directory,
      expanded = true,
      spacing = 1,
      sections = { { text = directory, group = "ProudMuted" } },
      children = directories[directory],
    })
  end

  local commit_children = {}
  for _, commit in ipairs(state.commits or {}) do
    local sha = tostring(commit.sha or "")
    table.insert(commit_children, {
      id = "commit:" .. sha,
      kind = "commit",
      label = commit.message or "",
      spacing = 1,
      sections = {
        { text = sha:sub(1, 7), group = "ProudAccentText" },
        { text = commit.message or "", group = "ProudBright" },
      },
      payload = { sha = sha },
    })
  end

  local check_children = {}
  for _, check in ipairs(state.checks or {}) do
    table.insert(check_children, {
      id = "check:" .. tostring(check.name),
      kind = "check",
      label = check.name or "",
      marker = "",
      spacing = { 1, 3 },
      sections = check_sections(check),
      payload = { status = check.status },
    })
  end

  return {
    root_node(
      "files",
      "Files",
      files_summary(#(state.files or {}), viewed),
      #file_children > 0 and file_children or loading_children(state, "files", "files")
    ),
    root_node(
      "commits",
      "Commits",
      #(state.commits or {}),
      #commit_children > 0 and commit_children or loading_children(state, "commits", "commits")
    ),
    root_node(
      "checks",
      "Checks",
      checks_summary(state.checks),
      #check_children > 0 and check_children or loading_children(state, "checks", "checks")
    ),
  }
end

function M.create(nodes, options)
  return tree_component.create(nodes, options)
end

function M.selected(state)
  return tree_component.selected(state)
end

function M.selected_file(state)
  local node = M.selected(state)
  return node and node.kind == "file" and node.payload or nil
end

function M.select_file(state, path)
  return tree_component.select(state, "file:" .. tostring(path))
end

function M.move(state, delta)
  return tree_component.move(state, delta)
end

function M.toggle(state, id)
  return tree_component.toggle(state, id)
end

function M.expand(state, id)
  return tree_component.expand(state, id)
end

function M.collapse(state, id)
  return tree_component.collapse(state, id)
end

function M.activate(state, options)
  return tree_component.activate(state, options)
end

function M.mark_viewed(state)
  local node = tree_component.selected(state)
  if not node or node.kind ~= "file" or not node.payload then
    return nil
  end
  local file = node.payload.file
  if file then
    file.viewed = true
    node.sections = section_row.normalize_sections(file_sections(file))
  end
  node.payload.viewed = true
  refresh_file_status(state)
  return node.payload.path
end

function M.render(state, width)
  return tree_component.render(state, width)
end

function M.sync_cursor(state, window)
  if not window or not vim.api.nvim_win_is_valid(window) then
    return false
  end
  local _, row = tree_component.row(state)
  if not row then
    return false
  end
  return pcall(vim.api.nvim_win_set_cursor, window, { row, 0 })
end

function M.move_selection(state, delta, options)
  options = options or {}
  if not M.move(state, delta) then
    return false
  end
  if options.on_change then
    options.on_change("selection")
  end
  M.sync_cursor(state, options.window)
  return true
end

-- options: window (or get_window() when the window can be re-created,
-- e.g. a hideable pane), refresh, on_open(file payload), on_activate(node)
-- for other leaves (commits), on_change, on_toggle_viewed.
function M.attach(buffer, state, options)
  options = options or {}
  local function window()
    if options.get_window then
      return options.get_window()
    end
    return options.window
  end
  local function refresh()
    if options.refresh then
      options.refresh()
    else
      local current = window()
      local width = current and vim.api.nvim_win_is_valid(current)
        and vim.api.nvim_win_get_width(current)
        or options.width
      ui.render(buffer, M.render(state, width))
    end
    M.sync_cursor(state, window())
  end
  state.refresh = refresh
  local function move(delta)
    return M.move_selection(state, delta, { on_change = options.on_change, window = window() })
  end
  state.move = move
  local function open_file()
    local selected = M.selected_file(state)
    if selected and options.on_open then
      options.on_open(selected)
    end
  end
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buffer,
    callback = function()
      if not vim.api.nvim_buf_is_valid(buffer) then
        return true
      end
      local current = vim.api.nvim_get_current_win()
      local own = window()
      if own and current ~= own then
        return
      end
      tree_component.select_row(state, vim.api.nvim_win_get_cursor(current)[1])
    end,
  })
  keymap.map(buffer, "n", "next_node", function()
    move(1)
  end, "Select the next sidebar node")
  keymap.map(buffer, "n", "previous_node", function()
    move(-1)
  end, "Select the previous sidebar node")
  keymap.map(buffer, "n", "toggle_node", function()
    if M.toggle(state) and options.on_change then
      options.on_change()
    end
    refresh()
  end, "Expand or collapse the selected sidebar node")
  keymap.map(buffer, "n", "expand_node", function()
    if M.expand(state) and options.on_change then
      options.on_change()
    end
    refresh()
  end, "Expand the selected sidebar branch")
  keymap.map(buffer, "n", "collapse_node", function()
    if M.collapse(state) and options.on_change then
      options.on_change()
    end
    refresh()
  end, "Collapse the selected sidebar branch")
  keymap.map(buffer, "n", "open_diff", open_file, "Open the selected file diff")
  keymap.map(buffer, "n", "open", function()
    local node = M.selected(state)
    if node and (#node.children > 0 or node.kind == "header") then
      M.toggle(state, node.id)
      if options.on_change then
        options.on_change()
      end
      refresh()
    elseif node and node.kind ~= "file" and options.on_activate then
      options.on_activate(node)
    else
      open_file()
    end
  end, "Activate the selected sidebar node")
  keymap.map(buffer, "n", "toggle_viewed", function()
    local path = M.mark_viewed(state)
    if path then
      if options.on_toggle_viewed then
        options.on_toggle_viewed(path)
      end
      if options.on_change then
        options.on_change()
      end
      refresh()
    end
  end, "Mark the selected file viewed")
  refresh()
end

function M.open(state, options)
  options = options or {}
  local name = options.name or "proud://sidebar"
  local workspace = ui.open_workspace(name, {
    {
      name = "sidebar",
      buffer_name = name .. "/sidebar",
      title = options.title or "Sidebar",
      view = M.render(state, options.width or 44),
      weight = options.weight or 1,
    },
  }, {
    focus = "sidebar",
    title = options.title or "Sidebar",
    statusline = options.statusline or "Sidebar",
  })
  state.workspace = workspace
  local buffer = ui.workspace_buffer(workspace, "sidebar")
  M.attach(buffer, state, vim.tbl_extend("force", options, {
    workspace = workspace,
    window = ui.workspace_window(workspace, "sidebar"),
  }))
  return buffer, workspace
end

return M
