-- Cursor-shape manager. Proud windows declare the shape they want with
-- set_window(); one WinEnter/BufEnter handler applies the shape of the
-- current window. Entering any non-Proud window restores the user's own
-- 'guicursor', captured at the moment Proud first changes it (not at load
-- time, so later user changes are respected).
local M = {}

M.shapes = {
  hidden = "a:block-ProudCursorHidden",
  accent = "a:block-ProudAccent",
}

local saved_guicursor
local group

local function apply(shape)
  local value = M.shapes[shape]
  if value then
    if saved_guicursor == nil then
      saved_guicursor = vim.o.guicursor
    end
    if vim.o.guicursor ~= value then
      vim.o.guicursor = value
    end
  elseif saved_guicursor ~= nil then
    vim.o.guicursor = saved_guicursor
    saved_guicursor = nil
  end
end

-- Applies the shape declared by the current window (or restores the user's
-- cursor when it declares none).
function M.refresh()
  local window = vim.api.nvim_get_current_win()
  apply(vim.w[window].proud_cursor)
end

function M.install()
  if group then
    return
  end
  group = vim.api.nvim_create_augroup("ProudCursor", { clear = true })
  vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
    group = group,
    callback = M.refresh,
  })
end

-- Declares the cursor shape for `window`: "hidden", "accent", or nil for
-- the user's own cursor. Takes effect immediately if it is the current
-- window, otherwise when the window is entered.
function M.set_window(window, shape)
  if not (type(window) == "number" and vim.api.nvim_win_is_valid(window)) then
    return
  end
  M.install()
  vim.w[window].proud_cursor = shape
  if window == vim.api.nvim_get_current_win() then
    apply(shape)
  end
end

-- Focuses `window` and applies its shape even when WinEnter is suppressed.
function M.focus(window)
  if not (type(window) == "number" and vim.api.nvim_win_is_valid(window)) then
    return false
  end
  vim.api.nvim_set_current_win(window)
  M.refresh()
  return true
end

return M
