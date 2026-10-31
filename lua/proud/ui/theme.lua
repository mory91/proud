local M = {}

local definitions = {}
local current_name
local applied_groups = {}
local manage_termguicolors = true

-- Whether apply() turns on 'termguicolors' (Proud's palettes are 24-bit).
function M.set_manage_termguicolors(value)
  manage_termguicolors = value ~= false
end

local function copy(value)
  return vim.deepcopy(value or {})
end

local function checked_name(name, level)
  if type(name) ~= "string" or name:match("^%s*$") then
    error("Theme name must be a non-empty string", level or 3)
  end
  return name
end

local function checked_definition(name, definition)
  if type(definition) ~= "table" then
    error(("Theme %q must be a table"):format(name), 3)
  end
  if type(definition.groups) ~= "table" or next(definition.groups) == nil then
    error(("Theme %q must define at least one highlight group"):format(name), 3)
  end
  if definition.extends ~= nil then
    checked_name(definition.extends, 3)
  end
  for group, style in pairs(definition.groups) do
    if type(group) ~= "string" or group == "" then
      error(("Theme %q contains an invalid highlight group name"):format(name), 3)
    end
    if type(style) ~= "table" then
      error(("Theme %q group %q must be a table"):format(name, group), 3)
    end
  end
end

local function resolve_groups(name, stack)
  checked_name(name, 4)
  local definition = definitions[name]
  if not definition then
    error(("Unknown theme %q"):format(name), 4)
  end
  stack = stack or {}
  if stack[name] then
    error(("Theme %q has an inheritance cycle"):format(name), 4)
  end
  stack[name] = true
  local groups = {}
  if definition.extends then
    groups = resolve_groups(definition.extends, stack)
  end
  for group, style in pairs(definition.groups) do
    groups[group] = vim.tbl_extend("force", groups[group] or {}, copy(style))
  end
  stack[name] = nil
  return groups
end

function M.register(name, definition, options)
  checked_name(name)
  checked_definition(name, definition)
  options = options or {}
  if definitions[name] and options.overwrite ~= true then
    error(("Theme %q is already registered"):format(name), 2)
  end
  definitions[name] = copy(definition)
  return copy(definition)
end

function M.replace(name, definition)
  return M.register(name, definition, { overwrite = true })
end

function M.list()
  local names = {}
  for name in pairs(definitions) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

function M.get(name)
  checked_name(name)
  return copy(resolve_groups(name))
end

function M.current()
  return current_name
end

function M.apply(name)
  local target = name or current_name
  checked_name(target)
  local groups = resolve_groups(target)
  local next_applied = {}
  if manage_termguicolors then
    vim.o.termguicolors = true
  end
  for group, style in pairs(groups) do
    vim.api.nvim_set_hl(0, group, copy(style))
    next_applied[group] = true
  end
  for group in pairs(applied_groups) do
    if not next_applied[group] then
      vim.api.nvim_set_hl(0, group, {})
    end
  end
  applied_groups = next_applied
  return copy(groups)
end

function M.use(name)
  checked_name(name)
  resolve_groups(name)
  current_name = name
  return M.apply(name)
end

return M
