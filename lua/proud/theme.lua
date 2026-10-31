local ui = require("proud.ui")

local M = {}

local dark = {
  ProudBackground = { fg = "#EAECF0", bg = "#101828" },
  ProudPanel = { fg = "#EAECF0", bg = "#1D2939" },
  ProudBorder = { fg = "#344054", bg = "#101828" },
  ProudAccent = { fg = "#FFFFFF", bg = "#7F56D9", bold = true },
  ProudAccentText = { fg = "#B692F6" },
  ProudMuted = { fg = "#98A2B3" },
  ProudText = { fg = "#EAECF0" },
  ProudBright = { fg = "#F9FAFB", bold = true },
  ProudSuccess = { fg = "#DCFAE6" },
  ProudSuccessText = { fg = "#0FAEA0" },
  ProudDanger = { fg = "#FEE4E2" },
  ProudDangerText = { fg = "#F04438" },
  ProudWarning = { fg = "#F79009" },
  ProudAdd = { fg = "#DCFAE6", bg = "#0E3131" },
  ProudDelete = { fg = "#FEE4E2", bg = "#381E27" },
  ProudSelection = { fg = "#F9FAFB", bg = "#253347" },
  ProudPreviewBorder = { fg = "#475467", blend = 35 },
  ProudPreviewTitle = { fg = "#98A2B3", blend = 35 },
  ProudCard = { fg = "#EAECF0", bg = "#101828" },
  ProudCardReply = { fg = "#EAECF0", bg = "#1D2939" },
  ProudCardSelected = { fg = "#EAECF0", bg = "#253347" },
  ProudCardBorder = { fg = "#475467", bg = "#101828" },
  ProudTabActive = { fg = "#F9FAFB", bg = "#101828", bold = true },
  ProudCursor = { fg = "#101828", bg = "#EAECF0" },
  ProudCursorHidden = { fg = "#101828", bg = "#101828", blend = 100 },
}

local light = {
  ProudBackground = { fg = "#101828", bg = "#F9FAFB" },
  ProudPanel = { fg = "#101828", bg = "#F2F4F7" },
  ProudBorder = { fg = "#98A2B3", bg = "#F9FAFB" },
  ProudAccent = { fg = "#FFFFFF", bg = "#6941C6", bold = true },
  ProudAccentText = { fg = "#5925DC" },
  ProudMuted = { fg = "#667085" },
  ProudText = { fg = "#101828" },
  ProudBright = { fg = "#0C111D", bold = true },
  ProudSuccess = { fg = "#027A48" },
  ProudSuccessText = { fg = "#027A48" },
  ProudDanger = { fg = "#B42318" },
  ProudDangerText = { fg = "#D92D20" },
  ProudWarning = { fg = "#DC6803" },
  ProudAdd = { fg = "#027A48", bg = "#ECFDF3" },
  ProudDelete = { fg = "#B42318", bg = "#FEF3F2" },
  ProudSelection = { fg = "#0C111D", bg = "#E4E7EC" },
  ProudPreviewBorder = { fg = "#98A2B3", blend = 35 },
  ProudPreviewTitle = { fg = "#667085", blend = 35 },
  ProudCard = { fg = "#101828", bg = "#F9FAFB" },
  ProudCardReply = { fg = "#101828", bg = "#F2F4F7" },
  ProudCardSelected = { fg = "#101828", bg = "#E4E7EC" },
  ProudCardBorder = { fg = "#98A2B3", bg = "#F9FAFB" },
  ProudTabActive = { fg = "#0C111D", bg = "#F9FAFB", bold = true },
  ProudCursor = { fg = "#F9FAFB", bg = "#101828" },
  ProudCursorHidden = { fg = "#F9FAFB", bg = "#F9FAFB", blend = 100 },
}

local function preset(base, groups)
  return {
    extends = base,
    groups = groups,
  }
end

local builtins = {
  ["proud-dark"] = { groups = dark },
  ["proud-light"] = { groups = light },
  ["proud-midnight"] = preset("proud-dark", {
    ProudBackground = { fg = "#E5E7EB", bg = "#080D18" },
    ProudPanel = { fg = "#E5E7EB", bg = "#111827" },
    ProudBorder = { fg = "#273449", bg = "#080D18" },
    ProudAccent = { fg = "#FFFFFF", bg = "#2563EB", bold = true },
    ProudAccentText = { fg = "#60A5FA" },
    ProudMuted = { fg = "#94A3B8" },
    ProudText = { fg = "#E5E7EB" },
    ProudBright = { fg = "#F8FAFC", bold = true },
    ProudAdd = { fg = "#BBF7D0", bg = "#0B2B22" },
    ProudDelete = { fg = "#FECACA", bg = "#35151D" },
    ProudSelection = { fg = "#F8FAFC", bg = "#172554" },
    ProudPreviewBorder = { fg = "#334155", blend = 35 },
    ProudPreviewTitle = { fg = "#94A3B8", blend = 35 },
    ProudCard = { fg = "#E5E7EB", bg = "#080D18" },
    ProudCardReply = { fg = "#E5E7EB", bg = "#111827" },
    ProudCardSelected = { fg = "#E5E7EB", bg = "#172554" },
    ProudCardBorder = { fg = "#334155", bg = "#080D18" },
    ProudTabActive = { fg = "#F8FAFC", bg = "#080D18", bold = true },
    ProudCursor = { fg = "#080D18", bg = "#E5E7EB" },
    ProudCursorHidden = { fg = "#080D18", bg = "#080D18", blend = 100 },
  }),
  ["proud-ocean"] = preset("proud-dark", {
    ProudBackground = { fg = "#D9F2F5", bg = "#071A22" },
    ProudPanel = { fg = "#D9F2F5", bg = "#0D2731" },
    ProudBorder = { fg = "#1B4652", bg = "#071A22" },
    ProudAccent = { fg = "#FFFFFF", bg = "#0E9FAD", bold = true },
    ProudAccentText = { fg = "#67E8F9" },
    ProudMuted = { fg = "#91B5BE" },
    ProudText = { fg = "#D9F2F5" },
    ProudBright = { fg = "#F0FDFF", bold = true },
    ProudAdd = { fg = "#C6F6E8", bg = "#0B3B36" },
    ProudDelete = { fg = "#FECDD3", bg = "#3A2028" },
    ProudSelection = { fg = "#F0FDFF", bg = "#123946" },
    ProudPreviewBorder = { fg = "#2B6470", blend = 35 },
    ProudPreviewTitle = { fg = "#91B5BE", blend = 35 },
    ProudCard = { fg = "#D9F2F5", bg = "#071A22" },
    ProudCardReply = { fg = "#D9F2F5", bg = "#0D2731" },
    ProudCardSelected = { fg = "#D9F2F5", bg = "#123946" },
    ProudCardBorder = { fg = "#2B6470", bg = "#071A22" },
    ProudTabActive = { fg = "#F0FDFF", bg = "#071A22", bold = true },
    ProudCursor = { fg = "#071A22", bg = "#D9F2F5" },
    ProudCursorHidden = { fg = "#071A22", bg = "#071A22", blend = 100 },
  }),
  ["proud-forest"] = preset("proud-dark", {
    ProudBackground = { fg = "#E1F2E7", bg = "#0D1712" },
    ProudPanel = { fg = "#E1F2E7", bg = "#14251B" },
    ProudBorder = { fg = "#294433", bg = "#0D1712" },
    ProudAccent = { fg = "#FFFFFF", bg = "#22A35A", bold = true },
    ProudAccentText = { fg = "#86EFAC" },
    ProudMuted = { fg = "#9AB9A5" },
    ProudText = { fg = "#E1F2E7" },
    ProudBright = { fg = "#F0FDF4", bold = true },
    ProudAdd = { fg = "#BBF7D0", bg = "#123B2B" },
    ProudDelete = { fg = "#FECACA", bg = "#3A2028" },
    ProudSelection = { fg = "#F0FDF4", bg = "#1B3827" },
    ProudPreviewBorder = { fg = "#3A6048", blend = 35 },
    ProudPreviewTitle = { fg = "#9AB9A5", blend = 35 },
    ProudCard = { fg = "#E1F2E7", bg = "#0D1712" },
    ProudCardReply = { fg = "#E1F2E7", bg = "#14251B" },
    ProudCardSelected = { fg = "#E1F2E7", bg = "#1B3827" },
    ProudCardBorder = { fg = "#3A6048", bg = "#0D1712" },
    ProudTabActive = { fg = "#F0FDF4", bg = "#0D1712", bold = true },
    ProudCursor = { fg = "#0D1712", bg = "#E1F2E7" },
    ProudCursorHidden = { fg = "#0D1712", bg = "#0D1712", blend = 100 },
  }),
  ["proud-sunset"] = preset("proud-dark", {
    ProudBackground = { fg = "#FBE9E4", bg = "#1C1217" },
    ProudPanel = { fg = "#FBE9E4", bg = "#2A1B22" },
    ProudBorder = { fg = "#51303B", bg = "#1C1217" },
    ProudAccent = { fg = "#FFFFFF", bg = "#F0642B", bold = true },
    ProudAccentText = { fg = "#FDBA74" },
    ProudMuted = { fg = "#C69AA4" },
    ProudText = { fg = "#FBE9E4" },
    ProudBright = { fg = "#FFF7ED", bold = true },
    ProudAdd = { fg = "#C6F6D8", bg = "#17382E" },
    ProudDelete = { fg = "#FECACA", bg = "#442127" },
    ProudSelection = { fg = "#FFF7ED", bg = "#3A222C" },
    ProudPreviewBorder = { fg = "#71404E", blend = 35 },
    ProudPreviewTitle = { fg = "#C69AA4", blend = 35 },
    ProudCard = { fg = "#FBE9E4", bg = "#1C1217" },
    ProudCardReply = { fg = "#FBE9E4", bg = "#2A1B22" },
    ProudCardSelected = { fg = "#FBE9E4", bg = "#3A222C" },
    ProudCardBorder = { fg = "#71404E", bg = "#1C1217" },
    ProudTabActive = { fg = "#FFF7ED", bg = "#1C1217", bold = true },
    ProudCursor = { fg = "#1C1217", bg = "#FBE9E4" },
    ProudCursorHidden = { fg = "#1C1217", bg = "#1C1217", blend = 100 },
  }),
  ["proud-paper"] = preset("proud-light", {
    ProudBackground = { fg = "#2B2925", bg = "#F7F3E8" },
    ProudPanel = { fg = "#2B2925", bg = "#EEE8D8" },
    ProudBorder = { fg = "#B7AA8B", bg = "#F7F3E8" },
    ProudAccent = { fg = "#FFFFFF", bg = "#9A5B2B", bold = true },
    ProudAccentText = { fg = "#9A4F18" },
    ProudMuted = { fg = "#746B5B" },
    ProudText = { fg = "#2B2925" },
    ProudBright = { fg = "#201E1A", bold = true },
    ProudAdd = { fg = "#276749", bg = "#E4F2E7" },
    ProudDelete = { fg = "#B42318", bg = "#F8E5E1" },
    ProudSelection = { fg = "#201E1A", bg = "#E5D8B8" },
    ProudPreviewBorder = { fg = "#B7AA8B", blend = 35 },
    ProudPreviewTitle = { fg = "#746B5B", blend = 35 },
    ProudCard = { fg = "#2B2925", bg = "#F7F3E8" },
    ProudCardReply = { fg = "#2B2925", bg = "#EEE8D8" },
    ProudCardSelected = { fg = "#2B2925", bg = "#E5D8B8" },
    ProudCardBorder = { fg = "#B7AA8B", bg = "#F7F3E8" },
    ProudTabActive = { fg = "#201E1A", bg = "#F7F3E8", bold = true },
    ProudCursor = { fg = "#F7F3E8", bg = "#2B2925" },
    ProudCursorHidden = { fg = "#F7F3E8", bg = "#F7F3E8", blend = 100 },
  }),
}

local function apply_tabline()
  _G.ProudTabline = function()
    local current = vim.fn.tabpagenr()
    local labels = {}
    for index = 1, vim.fn.tabpagenr("$") do
      local window = vim.fn.tabpagewinnr(index)
      local buffers = vim.fn.tabpagebuflist(index)
      local buffer = buffers[window] or buffers[1]
      local valid = type(buffer) == "number" and buffer >= 0 and vim.api.nvim_buf_is_valid(buffer)
      local name = valid and vim.api.nvim_buf_get_name(buffer) or ""
      local label = valid and vim.b[buffer].proud_title
        or (name == "" and "proud" or vim.fn.fnamemodify(name, ":t"))
      if index == current then
        labels[#labels + 1] = ("%%#ProudAccent#▌%%#ProudTabActive# %s "):format(label)
      else
        labels[#labels + 1] = ("%%#ProudPanel# %s %%#ProudBorder#│"):format(label)
      end
    end
    local repo = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
    return table.concat(labels) .. "%#ProudPanel#%=" .. "%#ProudBorder#│%#ProudPanel# " .. repo .. " "
  end
  vim.o.tabline = "%!v:lua.ProudTabline()"
end

local function install_builtins()
  for name, definition in pairs(builtins) do
    ui.themes.replace(name, definition)
  end
end

function M.setup(options)
  options = options or {}
  install_builtins()
  for name, definition in pairs(options.themes or {}) do
    ui.themes.replace(name, definition)
  end
  ui.themes.use(options.theme or "proud-dark")
  apply_tabline()
  return M.groups()
end

function M.apply()
  if not ui.themes.current() then
    return M.setup()
  end
  local groups = ui.themes.apply()
  apply_tabline()
  return groups
end

function M.groups()
  local current = ui.themes.current()
  if not current then
    return M.setup()
  end
  return ui.themes.get(current)
end

function M.builtin_names()
  local names = {}
  for name in pairs(builtins) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

return M
