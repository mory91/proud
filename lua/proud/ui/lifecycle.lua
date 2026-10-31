local M = {}

local function close_owned_window(window)
  if type(window) == "number" and vim.api.nvim_win_is_valid(window) then
    pcall(vim.api.nvim_win_close, window, true)
  end
end

local function delete_group(group)
  if group then
    pcall(vim.api.nvim_del_augroup_by_id, group)
  end
end

local scene_serial = 0

function M.create_scene_lifecycle(options)
  options = options or {}
  scene_serial = scene_serial + 1
  local scene_id = "proud_scene_" .. scene_serial
  local buffers = {}
  local windows = {}
  local closing = false
  local closed = false
  local group = vim.api.nvim_create_augroup("ProudScene" .. scene_serial, { clear = true })
  local lifecycle
  if options.tabpage and vim.api.nvim_tabpage_is_valid(options.tabpage) then
    vim.t[options.tabpage].proud_scene_id = scene_id
  end

  local function owns_tabpage(tabpage)
    return type(tabpage) == "number"
      and vim.api.nvim_tabpage_is_valid(tabpage)
      and vim.t[tabpage].proud_scene_id == scene_id
  end

  local function owns_window(window)
    return type(window) == "number"
      and vim.api.nvim_win_is_valid(window)
      and vim.w[window].proud_scene_id == scene_id
  end

  local function owns_buffer(buffer)
    return type(buffer) == "number"
      and vim.api.nvim_buf_is_valid(buffer)
      and vim.b[buffer].proud_scene_id == scene_id
  end

  local function cleanup()
    if closed then
      return
    end
    closed = true
    closing = false
    delete_group(group)
    if options.on_close then
      pcall(options.on_close, lifecycle)
    end
    local tabpage_replaced = options.tabpage
      and vim.api.nvim_tabpage_is_valid(options.tabpage)
      and not owns_tabpage(options.tabpage)
    if owns_tabpage(options.tabpage) then
      pcall(vim.api.nvim_set_current_tabpage, options.tabpage)
      pcall(vim.cmd, "tabclose")
    end
    if not tabpage_replaced then
      for window in pairs(windows) do
        if owns_window(window) then
          close_owned_window(window)
        end
      end
      for buffer in pairs(buffers) do
        if owns_buffer(buffer) then
          pcall(vim.api.nvim_buf_delete, buffer, { force = true })
        end
      end
    end
    if options.on_closed then
      pcall(options.on_closed, lifecycle)
    end
  end

  local function request_close()
    if closing or closed then
      return
    end
    closing = true
    vim.schedule(cleanup)
  end

  lifecycle = {
    scene_id = scene_id,
    tabpage = options.tabpage,
    group = group,
    closed = function()
      return closed
    end,
    close = cleanup,
    request_close = request_close,
    track_buffer = function(buffer)
      if type(buffer) == "number" then
        buffers[buffer] = scene_id
        if vim.api.nvim_buf_is_valid(buffer) then
          vim.b[buffer].proud_scene_id = scene_id
        end
      end
    end,
    track_window = function(window)
      if type(window) == "number" then
        windows[window] = scene_id
        if vim.api.nvim_win_is_valid(window) then
          vim.w[window].proud_scene_id = scene_id
        end
      end
    end,
  }

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(args)
      if buffers[args.buf] == scene_id then
        request_close()
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      local window = tonumber(args.match)
      if window and windows[window] == scene_id then
        request_close()
      end
    end,
  })
  return lifecycle
end

return M
