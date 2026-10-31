-- Floating-window primitive: one placement function drives both opening
-- and repositioning, so a float's geometry is defined in exactly one place.
--
--   local f = ui_float.create(buffer, {
--     enter = false,
--     placement = function()
--       return { row = 1, col = 2, width = 40, height = 1, zindex = 51 }
--     end,
--   })
--   f.reposition()  -- re-reads placement(), e.g. on VimResized
--   f.close()
--
-- placement() returns nvim_open_win config fields. Defaults:
-- relative = "editor", border = "none", style = "minimal", height = 1.
-- Returning nil from placement() skips the reposition (e.g. parent gone).
local M = {}

local function build(spec, creating)
  local placement = spec.placement()
  if not placement then
    return nil
  end
  local config = {}
  for key, value in pairs(placement) do
    config[key] = value
  end
  config.relative = config.relative or "editor"
  config.border = config.border or "none"
  config.style = config.style or "minimal"
  config.height = config.height or 1
  config.width = math.max(1, config.width or 1)
  -- noautocmd is only accepted by nvim_open_win, not nvim_win_set_config.
  config.noautocmd = creating and (spec.noautocmd ~= false) or nil
  return config
end

function M.create(buffer, spec)
  local float = { buffer = buffer }

  function float.is_valid()
    return type(float.window) == "number" and vim.api.nvim_win_is_valid(float.window)
  end

  function float.reposition()
    if not float.is_valid() then
      return false
    end
    local config = build(spec, false)
    if not config then
      return false
    end
    vim.api.nvim_win_set_config(float.window, config)
    return true
  end

  function float.close()
    if float.is_valid() then
      pcall(vim.api.nvim_win_close, float.window, true)
    end
  end

  float.window = vim.api.nvim_open_win(buffer, spec.enter == true, build(spec, true))
  return float
end

-- Placement anchored to another floating window, offset by rows/columns
-- and matching its width. Returns nil once the parent is closed.
function M.anchored(parent_window, offsets)
  offsets = offsets or {}
  return function()
    if not vim.api.nvim_win_is_valid(parent_window) then
      return nil
    end
    local parent = vim.api.nvim_win_get_config(parent_window)
    local row = (parent.row or 0) + (offsets.row or 0)
    if offsets.clamp_row then
      row = math.max(0, row)
    end
    return {
      row = row,
      col = (parent.col or 0) + (offsets.col or 0),
      width = math.max(1, parent.width or 1),
      height = offsets.height or 1,
      zindex = (parent.zindex or 50) + 1,
    }
  end
end

return M
