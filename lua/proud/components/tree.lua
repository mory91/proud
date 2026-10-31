local section_row = require("proud.components.section_row")
local text = require("proud.ui.text")

local M = {}

local spacing_cache = {}

local function spaces(count)
  count = math.max(0, math.floor(count or 0))
  local value = spacing_cache[count]
  if not value then
    value = string.rep(" ", count)
    spacing_cache[count] = value
  end
  return value
end

local function expandable(node)
  return node and (#node.children > 0 or node.kind == "header")
end

local function normalize_node(node, depth)
  if type(node) ~= "table" then
    error("tree node must be a table")
  end
  local label = tostring(node.label or node.id or "")
  local normalized = {
    id = tostring(node.id or label),
    label = label,
    kind = node.kind or "entry",
    expanded = node.expanded == true,
    spacing = node.spacing,
    marker = node.marker,
    payload = node.payload,
    depth = depth,
    children = {},
  }
  normalized.sections = section_row.normalize_sections(node.sections or { { text = label } })
  for _, child in ipairs(node.children or {}) do
    table.insert(normalized.children, normalize_node(child, depth + 1))
  end
  return normalized
end

function M.create(nodes, options)
  options = options or {}
  local roots = {}
  for _, node in ipairs(nodes or {}) do
    table.insert(roots, normalize_node(node, 0))
  end
  local state = {
    roots = roots,
    selected_id = options.selected_id,
  }
  local visible = M.flatten(state)
  if not state.selected_id and visible[1] then
    state.selected_id = visible[1].id
  end
  return state
end

function M.flatten(state)
  local visible = {}
  local function walk(nodes, parent_visible)
    for _, node in ipairs(nodes or {}) do
      if parent_visible then
        table.insert(visible, node)
      end
      if node.expanded then
        walk(node.children, parent_visible)
      end
    end
  end
  walk(state.roots, true)
  return visible
end

function M.find(state, id)
  id = tostring(id or "")
  local found
  local function walk(nodes)
    for _, node in ipairs(nodes or {}) do
      if node.id == id then
        found = node
        return
      end
      walk(node.children)
      if found then
        return
      end
    end
  end
  walk(state.roots)
  return found
end

function M.layout(state)
  local expanded = {}
  local function walk(nodes)
    for _, node in ipairs(nodes or {}) do
      if expandable(node) then
        expanded[node.id] = node.expanded == true
      end
      walk(node.children)
    end
  end
  walk(state.roots)
  return {
    selected_id = state.selected_id,
    expanded = expanded,
  }
end

function M.restore_layout(state, layout)
  layout = layout or {}
  local function walk(nodes)
    for _, node in ipairs(nodes or {}) do
      if layout.expanded and layout.expanded[node.id] ~= nil then
        node.expanded = layout.expanded[node.id] == true
      end
      walk(node.children)
    end
  end
  walk(state.roots)
  if layout.selected_id and M.find(state, layout.selected_id) then
    state.selected_id = layout.selected_id
  end
  return state
end

function M.selected(state)
  return M.find(state, state.selected_id)
end

function M.select_row(state, row)
  local node = M.flatten(state)[tonumber(row) or 0]
  if not node then
    return nil
  end
  state.selected_id = node.id
  return node
end

function M.select(state, id)
  local node = M.find(state, id)
  if not node then
    return false
  end
  local visible = M.flatten(state)
  for _, item in ipairs(visible) do
    if item.id == node.id then
      state.selected_id = node.id
      return true
    end
  end
  return false
end

function M.move(state, delta)
  local visible = M.flatten(state)
  if #visible == 0 then
    return false
  end
  local current_index = 1
  for index, node in ipairs(visible) do
    if node.id == state.selected_id then
      current_index = index
      break
    end
  end
  local next_index = math.max(1, math.min(#visible, current_index + (tonumber(delta) or 0)))
  if visible[next_index].id == state.selected_id then
    return false
  end
  state.selected_id = visible[next_index].id
  return true
end

local function set_expanded(state, node, expanded)
  if not expandable(node) or node.expanded == expanded then
    return false
  end
  node.expanded = expanded
  if not expanded then
    local visible_ids = {}
    for _, visible in ipairs(M.flatten(state)) do
      visible_ids[visible.id] = true
    end
    if not visible_ids[state.selected_id] then
      state.selected_id = node.id
    end
  end
  return true
end

function M.expand(state, id)
  local node = M.find(state, id or state.selected_id)
  return set_expanded(state, node, true)
end

function M.collapse(state, id)
  local node = M.find(state, id or state.selected_id)
  return set_expanded(state, node, false)
end

function M.toggle(state, id)
  local node = M.find(state, id or state.selected_id)
  if not expandable(node) then
    return false
  end
  return set_expanded(state, node, not node.expanded)
end

function M.activate(state, options)
  options = options or {}
  local node = M.selected(state)
  if not node then
    return "none"
  end
  if expandable(node) then
    M.toggle(state, node.id)
    return "toggle"
  end
  if options.on_open then
    options.on_open(node)
    return "open"
  end
  return "none"
end

function M.row(state, id)
  for index, node in ipairs(M.flatten(state)) do
    if node.id == id or node.id == state.selected_id and id == nil then
      return node, index
    end
  end
end

function M.render(state, width)
  local lines = {}
  local highlights = {}
  local parts = {}
  local line_count = 0
  local function render_node(node)
    local marker = node.marker
    if marker == nil then
      marker = expandable(node) and (node.expanded and "▾ " or "▸ ") or "  "
    end
    local prefix = spaces(node.depth * 2) .. marker
    parts[1] = prefix
    local part_count = section_row.append_flat(parts, 1, highlights, line_count, #prefix, node.sections, node.spacing)
    local line = table.concat(parts, "", 1, part_count)
    for index = 1, part_count do
      parts[index] = nil
    end
    if width and width > 0 then
      line = text.fit(line, width)
    end
    line_count = line_count + 1
    lines[line_count] = line
  end

  local function walk(nodes, parent_visible)
    for _, node in ipairs(nodes or {}) do
      if parent_visible then
        render_node(node)
      end
      if node.expanded then
        walk(node.children, parent_visible)
      end
    end
  end
  walk(state.roots, true)
  return {
    lines = lines,
    highlights = highlights,
    highlight_format = "flat",
  }
end

return M
