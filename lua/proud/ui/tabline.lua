-- Proud's themed tabline. Opt-in through enable(); disable() restores the
-- tabline the user had before. No global functions are installed: the
-- option evaluates this module through v:lua.require.
local M = {}

M.expression = "%!v:lua.require'proud.ui.tabline'.render()"

local previous

function M.render()
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

function M.enable()
  if vim.o.tabline ~= M.expression then
    previous = vim.o.tabline
    vim.o.tabline = M.expression
  end
end

function M.disable()
  if vim.o.tabline == M.expression then
    vim.o.tabline = previous or ""
    previous = nil
  end
end

function M.enabled()
  return vim.o.tabline == M.expression
end

return M
