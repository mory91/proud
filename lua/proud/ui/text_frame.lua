local M = {}

function M.open(window, options)
  options = options or {}
  if not vim.api.nvim_win_is_valid(window) then
    return nil
  end
  local frame = {
    host_window = window,
    buffer = options.buffer or vim.api.nvim_win_get_buf(window),
    requested_padding = math.max(0, math.floor(tonumber(options.padding) or 0)),
    normal_group = options.normal_group or "ProudBackground",
    namespace = vim.api.nvim_create_namespace("proud_text_frame"),
  }

  local function padding()
    local width = vim.api.nvim_win_get_width(frame.host_window)
    return math.min(frame.requested_padding, math.floor((width - 1) / 2))
  end

  function frame:geometry()
    if not vim.api.nvim_win_is_valid(self.host_window) or not vim.api.nvim_buf_is_valid(self.buffer) then
      return nil
    end
    local width = vim.api.nvim_win_get_width(self.host_window)
    local margin_width = padding()
    return {
      width = width,
      padding = margin_width,
      left_col = 0,
      right_col = math.max(0, width - margin_width),
    }
  end

  function frame:close()
    if vim.api.nvim_buf_is_valid(self.buffer) then
      vim.api.nvim_buf_clear_namespace(self.buffer, self.namespace, 0, -1)
    end
  end

  function frame:set_padding(value)
    self.requested_padding = math.max(0, math.floor(tonumber(value) or 0))
    self:resize()
  end

  function frame:resize()
    if not vim.api.nvim_win_is_valid(self.host_window) or not vim.api.nvim_buf_is_valid(self.buffer) then
      self:close()
      return
    end
    local geometry = self:geometry()
    if not geometry or geometry.padding <= 0 then
      self:close()
      return
    end
    local spaces = string.rep(" ", geometry.padding)
    local line_count = vim.api.nvim_buf_line_count(self.buffer)
    vim.api.nvim_buf_clear_namespace(self.buffer, self.namespace, 0, -1)
    for row = 0, line_count - 1 do
      vim.api.nvim_buf_set_extmark(self.buffer, self.namespace, row, 0, {
        virt_text = { { spaces, self.normal_group } },
        virt_text_win_col = geometry.left_col,
        priority = 10000,
      })
      vim.api.nvim_buf_set_extmark(self.buffer, self.namespace, row, 0, {
        virt_text = { { spaces, self.normal_group } },
        virt_text_win_col = geometry.right_col,
        priority = 10000,
      })
    end
  end

  frame:resize()
  return frame
end

function M.close(frame)
  if frame and frame.close then
    frame:close()
  end
end

function M.sync(pane, view)
  local padding = math.max(0, math.floor(tonumber(view and view.padding) or 0))
  if padding == 0 then
    M.close(pane.text_frame)
    pane.text_frame = nil
    return
  end
  if pane.text_frame then
    pane.text_frame:set_padding(padding)
  else
    pane.text_frame = M.open(pane.window, { padding = padding })
  end
end

function M.close_all(workspace)
  for _, pane in pairs(workspace.panes or {}) do
    M.close(pane.text_frame)
    pane.text_frame = nil
  end
end

return M
