-- Proud's color presets. Each built-in theme is a palette of 20 semantic
-- colors; derive() turns a palette into the full set of Proud highlight
-- groups, so every theme styles every surface consistently. Themes are
-- registered with the UI theme registry (proud.ui.theme).
local ui = require("proud.ui")

local M = {}

-- Palette fields, in display order. A palette must define all of them,
-- directly or through `extends`.
M.fields = {
  "background", "panel", "border", "text", "muted", "bright",
  "accent", "on_accent", "accent_text", "selection", "subtle_border",
  "success", "success_text", "danger", "danger_text", "warning",
  "add_fg", "add_bg", "delete_fg", "delete_bg",
}

local builtins = {
  ["proud-dark"] = {
    palette = {
      background = "#101828",
      panel = "#1D2939",
      border = "#344054",
      text = "#EAECF0",
      muted = "#98A2B3",
      bright = "#F9FAFB",
      accent = "#7F56D9",
      on_accent = "#FFFFFF",
      accent_text = "#B692F6",
      selection = "#253347",
      subtle_border = "#475467",
      success = "#DCFAE6",
      success_text = "#0FAEA0",
      danger = "#FEE4E2",
      danger_text = "#F04438",
      warning = "#F79009",
      add_fg = "#DCFAE6",
      add_bg = "#0E3131",
      delete_fg = "#FEE4E2",
      delete_bg = "#381E27",
    },
  },
  ["proud-light"] = {
    palette = {
      background = "#F9FAFB",
      panel = "#F2F4F7",
      border = "#98A2B3",
      text = "#101828",
      muted = "#667085",
      bright = "#0C111D",
      accent = "#6941C6",
      on_accent = "#FFFFFF",
      accent_text = "#5925DC",
      selection = "#E4E7EC",
      subtle_border = "#98A2B3",
      success = "#027A48",
      success_text = "#027A48",
      danger = "#B42318",
      danger_text = "#D92D20",
      warning = "#DC6803",
      add_fg = "#027A48",
      add_bg = "#ECFDF3",
      delete_fg = "#B42318",
      delete_bg = "#FEF3F2",
    },
  },
  ["proud-midnight"] = {
    extends = "proud-dark",
    palette = {
      background = "#080D18",
      panel = "#111827",
      border = "#273449",
      text = "#E5E7EB",
      muted = "#94A3B8",
      bright = "#F8FAFC",
      accent = "#2563EB",
      accent_text = "#60A5FA",
      selection = "#172554",
      subtle_border = "#334155",
      add_fg = "#BBF7D0",
      add_bg = "#0B2B22",
      delete_fg = "#FECACA",
      delete_bg = "#35151D",
    },
  },
  ["proud-ocean"] = {
    extends = "proud-dark",
    palette = {
      background = "#071A22",
      panel = "#0D2731",
      border = "#1B4652",
      text = "#D9F2F5",
      muted = "#91B5BE",
      bright = "#F0FDFF",
      accent = "#0E9FAD",
      accent_text = "#67E8F9",
      selection = "#123946",
      subtle_border = "#2B6470",
      add_fg = "#C6F6E8",
      add_bg = "#0B3B36",
      delete_fg = "#FECDD3",
      delete_bg = "#3A2028",
    },
  },
  ["proud-forest"] = {
    extends = "proud-dark",
    palette = {
      background = "#0D1712",
      panel = "#14251B",
      border = "#294433",
      text = "#E1F2E7",
      muted = "#9AB9A5",
      bright = "#F0FDF4",
      accent = "#22A35A",
      accent_text = "#86EFAC",
      selection = "#1B3827",
      subtle_border = "#3A6048",
      add_fg = "#BBF7D0",
      add_bg = "#123B2B",
      delete_fg = "#FECACA",
      delete_bg = "#3A2028",
    },
  },
  ["proud-sunset"] = {
    extends = "proud-dark",
    palette = {
      background = "#1C1217",
      panel = "#2A1B22",
      border = "#51303B",
      text = "#FBE9E4",
      muted = "#C69AA4",
      bright = "#FFF7ED",
      accent = "#F0642B",
      accent_text = "#FDBA74",
      selection = "#3A222C",
      subtle_border = "#71404E",
      add_fg = "#C6F6D8",
      add_bg = "#17382E",
      delete_fg = "#FECACA",
      delete_bg = "#442127",
    },
  },
  ["proud-paper"] = {
    extends = "proud-light",
    palette = {
      background = "#F7F3E8",
      panel = "#EEE8D8",
      border = "#B7AA8B",
      text = "#2B2925",
      muted = "#746B5B",
      bright = "#201E1A",
      accent = "#9A5B2B",
      accent_text = "#9A4F18",
      selection = "#E5D8B8",
      subtle_border = "#B7AA8B",
      add_fg = "#276749",
      add_bg = "#E4F2E7",
      delete_bg = "#F8E5E1",
    },
  },
}

-- Order in which built-ins are resolved (bases before their extensions).
local builtin_order = {
  "proud-dark", "proud-light",
  "proud-midnight", "proud-ocean", "proud-forest", "proud-sunset",
  "proud-paper",
}

-- Maps a complete palette to Proud's highlight groups.
function M.derive(p)
  return {
    ProudBackground = { fg = p.text, bg = p.background },
    ProudPanel = { fg = p.text, bg = p.panel },
    ProudBorder = { fg = p.border, bg = p.background },
    ProudAccent = { fg = p.on_accent, bg = p.accent, bold = true },
    ProudAccentText = { fg = p.accent_text },
    ProudMuted = { fg = p.muted },
    ProudText = { fg = p.text },
    ProudBright = { fg = p.bright, bold = true },
    ProudSuccess = { fg = p.success },
    ProudSuccessText = { fg = p.success_text },
    ProudDanger = { fg = p.danger },
    ProudDangerText = { fg = p.danger_text },
    ProudWarning = { fg = p.warning },
    ProudAdd = { fg = p.add_fg, bg = p.add_bg },
    ProudDelete = { fg = p.delete_fg, bg = p.delete_bg },
    ProudSelection = { fg = p.bright, bg = p.selection },
    ProudPreviewBorder = { fg = p.subtle_border, blend = 35 },
    ProudPreviewTitle = { fg = p.muted, blend = 35 },
    ProudCard = { fg = p.text, bg = p.background },
    ProudCardReply = { fg = p.text, bg = p.panel },
    ProudCardSelected = { fg = p.text, bg = p.selection },
    ProudCardBorder = { fg = p.subtle_border, bg = p.background },
    ProudTabActive = { fg = p.bright, bg = p.background, bold = true },
    ProudCursor = { fg = p.background, bg = p.text },
    ProudCursorHidden = { fg = p.background, bg = p.background, blend = 100 },
  }
end

-- Resolved palettes by theme name (built-ins and palette-based custom themes).
local palettes = {}

local function resolve_palette(name, definition)
  local palette = {}
  if definition.extends then
    local base = palettes[definition.extends]
    if not base then
      error(("Theme %q extends %q, which has no palette"):format(name, definition.extends), 3)
    end
    palette = vim.deepcopy(base)
  end
  for field, value in pairs(definition.palette) do
    palette[field] = value
  end
  for _, field in ipairs(M.fields) do
    if palette[field] == nil then
      error(("Theme %q palette is missing %q"):format(name, field), 3)
    end
  end
  return palette
end

-- Turns a theme definition into a registry definition. Palette themes are
-- fully derived (plus any explicit group overrides); group-only themes
-- pass through and inherit through the registry as before.
local function to_registry(name, definition)
  if not definition.palette then
    return definition
  end
  local palette = resolve_palette(name, definition)
  palettes[name] = palette
  local groups = M.derive(palette)
  for group, style in pairs(definition.groups or {}) do
    groups[group] = vim.tbl_extend("force", groups[group] or {}, style)
  end
  return { groups = groups }
end

local function install(definitions, order)
  local pending = vim.deepcopy(definitions)
  local function register(name)
    local definition = pending[name]
    if not definition then
      return
    end
    pending[name] = nil
    if definition.palette and definition.extends and pending[definition.extends] then
      register(definition.extends)
    end
    ui.themes.replace(name, to_registry(name, definition))
  end
  for _, name in ipairs(order or {}) do
    register(name)
  end
  local names = vim.tbl_keys(pending)
  table.sort(names)
  for _, name in ipairs(names) do
    register(name)
  end
end

-- Registers built-ins and options.themes, then selects options.theme.
-- Custom themes may give `palette` (any subset when extending a palette
-- theme), `groups`, or both; `groups` always wins over derived values.
function M.setup(options)
  options = options or {}
  install(builtins, builtin_order)
  install(options.themes or {})
  ui.themes.use(options.theme or "proud-dark")
  return M.groups()
end

function M.apply()
  if not ui.themes.current() then
    return M.setup()
  end
  return ui.themes.apply()
end

function M.groups()
  local current = ui.themes.current()
  if not current then
    return M.setup()
  end
  return ui.themes.get(current)
end

function M.builtin_names()
  local names = vim.tbl_keys(builtins)
  table.sort(names)
  return names
end

-- Returns a copy of a resolved palette, or nil for group-only themes.
function M.palette(name)
  return palettes[name] and vim.deepcopy(palettes[name]) or nil
end

return M
