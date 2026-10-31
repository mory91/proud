local themes = require("proud.ui.theme")
local geometry_math = require("proud.ui.geometry")

local M = {
  themes = themes,
}

local namespace = vim.api.nvim_create_namespace("proud")
local buffer_lifecycle_group = vim.api.nvim_create_augroup("ProudBufferLifecycle", { clear = true })
local default_guicursor = vim.o.guicursor
local layout = {
  margin = { top = 3, bottom = 2, left = 2, right = 2 },
  gap = 3,
}

vim.api.nvim_create_autocmd("QuitPre", {
  group = buffer_lifecycle_group,
  callback = function()
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buffer) and vim.b[buffer].proud_buffer then
        vim.bo[buffer].modified = false
      end
    end
  end,
})

function M.add_theme(name, definition, options)
  return themes.register(name, definition, options)
end

function M.use_theme(name)
  return themes.use(name)
end

function M.current_theme()
  return themes.current()
end

local function nonnegative_integer(value, fallback)
  value = tonumber(value)
  if not value or value < 0 then
    return fallback
  end
  return math.floor(value)
end

function M.configure(options)
  options = options or {}
  local windows = options.windows or options
  local margin = windows.margin or {}
  layout.margin.top = nonnegative_integer(margin.top, layout.margin.top)
  layout.margin.bottom = nonnegative_integer(margin.bottom, layout.margin.bottom)
  layout.margin.left = nonnegative_integer(margin.left, layout.margin.left)
  layout.margin.right = nonnegative_integer(margin.right, layout.margin.right)
  layout.gap = nonnegative_integer(windows.gap, layout.gap)
  return M.layout_config()
end

function M.layout_config()
  return vim.deepcopy(layout)
end

local function mark_line(item)
  return item.line or item[1]
end

local function mark_start(item)
  return item.start_col or item[2] or 0
end

local function mark_end(item, line)
  return item.end_col or item[3] or #line
end

local function mark_group(item)
  return item.group or item[4]
end

local function title_for(name)
  if name == "proud://prs" then
    return "proud: pull requests"
  end
  if name == "proud://prs/preview" then
    return "Preview"
  end
  if name:match("^proud://help") then
    return "Proud help"
  end
  local number, mode = name:match("^proud://pr/(%d+)/diff/(%w+)$")
  if number then
    return ("#%s diff · %s"):format(number, mode)
  end
  number = name:match("^proud://pr/(%d+)/overview$")
  if number then
    return ("#%s overview"):format(number)
  end
  local compare = name:match("^proud://compare/(.+)$")
  if compare then
    return "compare  " .. compare
  end
  return name:gsub("^proud://", "")
end

local function decorate_window(window, buffer, name, options)
  options = options or {}
  vim.o.guicursor = options.hide_cursor and "a:block-ProudCursorHidden" or default_guicursor
  local normal_group = options.normal_group or "ProudBackground"
  local normal_nc_group = options.normal_nc_group or normal_group
  local float_group = options.float_group or "ProudBackground"
  local float_border = options.float_border or "ProudAccentText"
  local float_title = options.float_title or "ProudAccentText"
  local winhighlight = {
    "Normal:" .. normal_group,
    "NormalNC:" .. normal_nc_group,
    "EndOfBuffer:ProudBorder",
    "StatusLine:ProudPanel",
    "StatusLineNC:ProudPanel",
    "TabLine:ProudPanel",
    "TabLineSel:ProudTabActive",
    "WinSeparator:ProudBorder",
    "NormalFloat:" .. float_group,
    "FloatBorder:" .. float_border,
    "FloatTitle:" .. float_title,
    "CursorLine:ProudSelection",
  }
  if options.hide_cursor then
    table.insert(winhighlight, "Cursor:ProudCursorHidden")
    table.insert(winhighlight, "lCursor:ProudCursorHidden")
    table.insert(winhighlight, "CursorIM:ProudCursorHidden")
  end
  vim.wo[window].winhighlight = table.concat(winhighlight, ",")
  vim.wo[window].number = false
  vim.wo[window].relativenumber = false
  vim.wo[window].signcolumn = "no"
  vim.wo[window].cursorline = options.cursorline ~= false
  vim.wo[window].wrap = false
  vim.wo[window].linebreak = false
  vim.wo[window].breakindent = false
  vim.wo[window].showbreak = ""
  vim.b[buffer].proud_title = options.title or title_for(name)
  vim.wo[window].statusline = table.concat({
    "%#ProudAccent# NORMAL ",
    "%#ProudBorder# ▎ ",
    "%#ProudBright# ",
    options.statusline or vim.b[buffer].proud_title,
    " ",
    "%#ProudBorder#▎",
    "%<",
    "%#ProudPanel#%=",
    "%#ProudMuted# GitHub ",
    "%#ProudSuccessText# api ",
    "%#ProudSuccess#✓ ",
    "%#ProudPanel# ",
  })
end

local function display_width(value)
  if not value:find("[\128-\255]") then
    return #value
  end
  return vim.fn.strdisplaywidth(value)
end

function M.fit(value, width)
  value = tostring(value or "")
  width = math.max(1, math.floor(width))
  local value_width = display_width(value)
  if value_width <= width then
    return value .. string.rep(" ", width - value_width)
  end
  if not value:find("[\128-\255]") then
    return value:sub(1, width)
  end

  local clipped = vim.fn.strcharpart(value, 0, width)
  while display_width(clipped) > width do
    clipped = vim.fn.strcharpart(clipped, 0, math.max(0, vim.fn.strchars(clipped) - 1))
  end
  return clipped .. string.rep(" ", width - display_width(clipped))
end

local function should_wrap(options)
  if options and options.wrap ~= nil then
    return options.wrap == true
  end
  return vim.go.wrap == true
end

function M.wrap_text(value, width, options)
  options = options or {}
  width = math.max(1, math.floor(width or 80))
  value = tostring(value or "")
  local sources = { value }
  if value:find("\n", 1, true) then
    sources = vim.split(value, "\n", { plain = true })
  end
  if not should_wrap(options) then
    return sources
  end
  local lines = {}
  for _, source in ipairs(sources) do
    if source == "" or display_width(source) <= width then
      table.insert(lines, source)
    else
      source = source:gsub("%s+", " ")
      local current = ""
      for word in source:gmatch("%S+") do
        while display_width(word) > width do
          local cut = 0
          for index = 1, vim.fn.strchars(word) do
            local candidate = vim.fn.strcharpart(word, 0, index)
            if display_width(candidate) > width then
              break
            end
            cut = index
          end
          if cut == 0 then
            cut = 1
          end
          local piece = vim.fn.strcharpart(word, 0, cut)
          if current ~= "" then
            table.insert(lines, current)
            current = ""
          end
          table.insert(lines, piece)
          word = vim.fn.strcharpart(word, cut)
        end
        local candidate = current == "" and word or current .. " " .. word
        if display_width(candidate) > width and current ~= "" then
          table.insert(lines, current)
          current = word
        else
          current = candidate
        end
      end
      table.insert(lines, current)
    end
  end
  return lines
end

function M.content_lines(value, options)
  options = options or {}
  local width = math.max(1, math.floor(options.width or 80))
  local padding = math.max(0, math.floor(options.padding or 0))
  padding = math.min(padding, math.floor((width - 1) / 2))
  local inner_width = width - padding * 2
  local prefix = string.rep(" ", padding)
  local suffix = string.rep(" ", padding)
  local result = {}
  local wrap_enabled = should_wrap(options)
  for _, line in ipairs(M.wrap_text(value, inner_width, { wrap = wrap_enabled })) do
    local content = wrap_enabled and M.fit(line, inner_width) or line
    table.insert(result, prefix .. content .. suffix)
  end
  return result
end

function M.open_text_frame(window, options)
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

function M.close_text_frame(frame)
  if frame and frame.close then
    frame:close()
  end
end

local function sync_text_frame(pane, view)
  local padding = math.max(0, math.floor(tonumber(view and view.padding) or 0))
  if padding == 0 then
    M.close_text_frame(pane.text_frame)
    pane.text_frame = nil
    return
  end
  if pane.text_frame then
    pane.text_frame:set_padding(padding)
  else
    pane.text_frame = M.open_text_frame(pane.window, { padding = padding })
  end
end

local function close_text_frames(workspace)
  for _, pane in pairs(workspace.panes or {}) do
    M.close_text_frame(pane.text_frame)
    pane.text_frame = nil
  end
end

function M.fit_view(view, width)
  local lines = {}
  for _, line in ipairs(view.lines or {}) do
    table.insert(lines, tostring(line or ""))
  end
  return {
    lines = lines,
    highlights = view.highlights or {},
    highlight_format = view.highlight_format,
  }
end

local function shift_view_rows(view, row_offset)
  local lines = {}
  local row_width = display_width((view.lines or {})[1] or "")
  for _ = 1, row_offset do
    table.insert(lines, string.rep(" ", row_width))
  end
  for _, line in ipairs(view.lines or {}) do
    table.insert(lines, line)
  end
  local highlights = {}
  if view.highlight_format == "flat" then
    for index = 1, #(view.highlights or {}), 4 do
      table.insert(highlights, view.highlights[index] + row_offset)
      table.insert(highlights, view.highlights[index + 1])
      table.insert(highlights, view.highlights[index + 2])
      table.insert(highlights, view.highlights[index + 3])
    end
  else
    for _, item in ipairs(view.highlights or {}) do
      local shifted = vim.deepcopy(item)
      if shifted.line ~= nil then
        shifted.line = shifted.line + row_offset
      elseif shifted[1] ~= nil then
        shifted[1] = shifted[1] + row_offset
      end
      table.insert(highlights, shifted)
    end
  end
  return {
    lines = lines,
    highlights = highlights,
    highlight_format = view.highlight_format,
  }
end

function M.divide_view(view)
  local left = { lines = {}, highlights = {} }
  local right = { lines = {}, highlights = {} }
  for line_index, line in ipairs(view.lines or {}) do
    local separator = line:find("│ ", 1, true)
    if separator then
      local right_start = separator + 3
      local right_content_offset = separator + 2
      table.insert(left.lines, line:sub(1, separator - 1))
      table.insert(right.lines, line:sub(right_start))
      for _, item in ipairs(view.highlights or {}) do
        if mark_line(item) == line_index - 1 then
          local start_col = mark_start(item)
          local end_col = mark_end(item, line)
          if start_col < separator - 1 then
            table.insert(left.highlights, { line_index - 1, start_col, math.min(end_col, separator - 1), mark_group(item) })
          elseif end_col > right_content_offset then
            table.insert(right.highlights, {
              line_index - 1,
              math.max(0, start_col - right_content_offset),
              math.max(0, end_col - right_content_offset),
              mark_group(item),
            })
          end
        end
      end
    else
      table.insert(left.lines, line)
      table.insert(right.lines, "")
    end
  end
  return left, right
end

local function prepare_buffer(name)
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buffer) and vim.api.nvim_buf_get_name(buffer) == name then
      vim.bo[buffer].buftype = "nofile"
      vim.bo[buffer].bufhidden = "hide"
      vim.bo[buffer].swapfile = false
      vim.bo[buffer].modifiable = false
      vim.b[buffer].proud_buffer = true
      return buffer
    end
  end
  local buffer = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, buffer, name)
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "hide"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].modifiable = false
  vim.b[buffer].proud_buffer = true
  return buffer
end

local function delete_owned_buffers(buffers)
  for _, buffer in ipairs(buffers or {}) do
    if type(buffer) == "number" and vim.api.nvim_buf_is_valid(buffer) then
      pcall(vim.api.nvim_buf_delete, buffer, { force = true })
    end
  end
end

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

function M.buffer(name)
  return prepare_buffer(name)
end

function M.render(buffer, view, options)
  options = options or {}
  if (options.top_pad or 0) > 0 then
    view = shift_view_rows(view, options.top_pad)
  end
  local lines = {}
  for index, value in ipairs(view.lines or {}) do
    lines[index] = (tostring(value):gsub("\r\n", "\n"):gsub("[\r\n]", " "))
  end
  local highlights = view.highlights or {}
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
    if view.highlight_format == "flat" then
      for index = 1, #highlights, 4 do
        local row = highlights[index]
        local line = lines[row + 1] or ""
        local start_col = math.max(0, math.min(highlights[index + 1], #line))
        local end_col = math.max(start_col, math.min(highlights[index + 2], #line))
        if end_col > start_col then
          vim.api.nvim_buf_set_extmark(buffer, namespace, row, start_col, {
            end_col = end_col,
            hl_group = highlights[index + 3],
          })
        end
      end
    else
      for _, item in ipairs(highlights) do
        local row = mark_line(item)
        local line = lines[row + 1] or ""
        local start_col = math.max(0, math.min(mark_start(item), #line))
        local end_col = math.max(start_col, math.min(mark_end(item, line), #line))
        if end_col > start_col then
          vim.api.nvim_buf_set_extmark(buffer, namespace, row, start_col, {
            end_col = end_col,
            hl_group = mark_group(item),
          })
        end
      end
  end
  vim.bo[buffer].modifiable = false
end

local function header_mark(buffer, start_col, end_col, group)
  if end_col > start_col then
    vim.api.nvim_buf_set_extmark(buffer, namespace, 0, start_col, {
      end_col = end_col,
      hl_group = group,
    })
  end
end

function M.open_pane_header(parent_window, options)
  options = options or {}
  local parent = vim.api.nvim_win_get_config(parent_window)
  local width = math.max(1, parent.width or 1)
  local function current_width()
    if vim.api.nvim_win_is_valid(parent_window) then
      return math.max(1, vim.api.nvim_win_get_config(parent_window).width or 1)
    end
    return width
  end
  local buffer = prepare_buffer(options.buffer_name or "proud://pane/header")
  local editable = options.editable or options.prompt ~= nil
  local function normalize_segments(value)
    if type(value) == "table" then
      return value
    end
    local text = tostring(value or "")
    if text == "" then
      return {}
    end
    return { { text = text, group = options.trailing_group or "ProudMuted" } }
  end
  vim.bo[buffer].buftype = editable and "prompt" or "nofile"
  vim.bo[buffer].modifiable = editable
  local prompt = editable and tostring(options.prompt or "") or ""
  if editable then
    vim.fn.prompt_setprompt(buffer, prompt)
  end
  local window = vim.api.nvim_open_win(buffer, editable and options.focusable ~= false, {
    relative = "editor",
    row = options.inside and (parent.row or 0) + 1 or math.max(0, (parent.row or 0) - 1),
    col = options.inside and (parent.col or 0) + 1 or parent.col or 0,
    width = width,
    height = 1,
    border = "none",
    style = "minimal",
    noautocmd = true,
    zindex = (parent.zindex or 50) + 1,
  })
  vim.wo[window].winhighlight = table.concat({
    "Normal:" .. (options.normal_group or "ProudBackground"),
    "NormalNC:" .. (options.normal_group or "ProudBackground"),
    "NormalFloat:" .. (options.normal_group or "ProudBackground"),
    "FloatBorder:" .. (options.border_group or "ProudBorder"),
    "Cursor:" .. (options.cursor_group or "ProudAccent"),
    "lCursor:" .. (options.cursor_group or "ProudAccent"),
    "CursorIM:" .. (options.cursor_group or "ProudAccent"),
    "Prompt:" .. (options.prompt_group or "ProudAccentText"),
    "EndOfBuffer:ProudBorder",
  }, ",")
  vim.wo[window].number = false
  vim.wo[window].relativenumber = false
  vim.wo[window].signcolumn = "no"
  vim.wo[window].cursorline = false
  vim.wo[window].wrap = false
  vim.wo[window].linebreak = false
  vim.wo[window].breakindent = false
  vim.b[buffer].proud_title = options.title or "proud header"
  local header = {
    buffer = buffer,
    window = window,
    parent_window = parent_window,
    inside = options.inside == true,
    editable = editable,
    prompt = prompt,
    trailing_segments = normalize_segments(options.trailing_text or options.trailing_segments),
    silent = false,
  }

  function header.get_value()
    if not vim.api.nvim_buf_is_valid(buffer) then
      return ""
    end
    local line = vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] or ""
    if prompt ~= "" and line:sub(1, #prompt) == prompt then
      return line:sub(#prompt + 1)
    end
    return line
  end

  function header.render()
    if not vim.api.nvim_buf_is_valid(buffer) then
      return
    end
    vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
    if not editable then
    local text = M.fit(options.text or "", current_width())
      vim.bo[buffer].modifiable = true
      vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { text })
      vim.bo[buffer].modifiable = false
      header_mark(buffer, 0, #text, options.text_group or "ProudAccentText")
      local trailing = {}
      for _, segment in ipairs(header.trailing_segments) do
        local segment_text = tostring(segment.text or "")
        if segment_text ~= "" then
          table.insert(trailing, { segment_text, segment.group or options.trailing_group or "ProudMuted" })
        end
      end
      if #trailing > 0 then
        vim.api.nvim_buf_set_extmark(buffer, namespace, 0, #text, {
          virt_text = trailing,
          virt_text_pos = "right_align",
        })
      end
      return
    end
    local line = vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] or prompt
    local offset = 0
    for _, segment in ipairs(options.prompt_segments or {}) do
      local segment_text = tostring(segment.text or "")
      if line:sub(offset + 1, offset + #segment_text) == segment_text then
        header_mark(buffer, offset, offset + #segment_text, segment.group or options.prompt_group or "ProudAccentText")
      end
      offset = offset + #segment_text
    end
    if offset < #prompt then
      header_mark(buffer, offset, #prompt, options.prompt_group or "ProudAccentText")
    end
    local value = header.get_value()
    if value == "" and options.placeholder then
      vim.api.nvim_buf_set_extmark(buffer, namespace, 0, #line, {
        virt_text = { { options.placeholder, options.placeholder_group or "ProudMuted" } },
        virt_text_pos = "eol",
      })
    else
      header_mark(buffer, #prompt, #line, options.value_group or "ProudBright")
    end
    local trailing = {}
    for _, segment in ipairs(header.trailing_segments) do
      local segment_text = tostring(segment.text or "")
      if segment_text ~= "" then
        table.insert(trailing, { segment_text, segment.group or options.trailing_group or "ProudMuted" })
      end
    end
    if #trailing > 0 then
      vim.api.nvim_buf_set_extmark(buffer, namespace, 0, #line, {
        virt_text = trailing,
        virt_text_pos = "right_align",
      })
    end
  end

  function header.set_trailing(value)
    header.trailing_segments = normalize_segments(value)
    header.render()
  end

  function header.get_trailing_text()
    local values = {}
    for _, segment in ipairs(header.trailing_segments) do
      table.insert(values, tostring(segment.text or ""))
    end
    return table.concat(values)
  end

  function header.set_value(value, notify)
    if not vim.api.nvim_buf_is_valid(buffer) then
      return
    end
    value = tostring(value or "")
    header.silent = true
    vim.bo[buffer].modifiable = true
    if editable then
      vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { prompt .. value })
    else
      vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { M.fit(value, current_width()) })
    end
    vim.bo[buffer].modifiable = editable
    header.render()
    if editable and vim.api.nvim_win_is_valid(window) then
      local line = vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] or prompt
      pcall(vim.api.nvim_win_set_cursor, window, { 1, #line })
    end
    header.silent = false
    if notify and editable and options.on_change then
      options.on_change(header.get_value())
    end
  end

  function header.focus(start_insert)
    if vim.api.nvim_win_is_valid(window) then
      vim.api.nvim_set_current_win(window)
      if editable then
        vim.o.guicursor = default_guicursor
        if start_insert then
          vim.cmd("startinsert!")
        end
      end
    end
  end

  function header.resize()
    if not vim.api.nvim_win_is_valid(parent_window) or not vim.api.nvim_win_is_valid(window) then
      return
    end
    local current_parent = vim.api.nvim_win_get_config(parent_window)
    local current_width = math.max(1, current_parent.width or 1)
    vim.api.nvim_win_set_config(window, {
      relative = "editor",
      row = options.inside and (current_parent.row or 0) + 1 or math.max(0, (current_parent.row or 0) - 1),
      col = options.inside and (current_parent.col or 0) + 1 or current_parent.col or 0,
      width = current_width,
      height = 1,
      border = "none",
      style = "minimal",
      zindex = (current_parent.zindex or 50) + 1,
    })
    header.render()
  end

  if editable then
    vim.fn.prompt_setcallback(buffer, function(value)
      vim.schedule(function()
        header.set_value(value)
        if options.on_submit then
          options.on_submit(value)
        end
      end)
    end)
    local group = vim.api.nvim_create_augroup("ProudHeader" .. tostring(buffer), { clear = true })
    vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
      group = group,
      buffer = buffer,
      callback = function()
        if not header.silent then
          header.render()
          if options.on_change then
            options.on_change(header.get_value())
          end
        end
      end,
    })
    vim.api.nvim_create_autocmd("BufLeave", {
      group = group,
      buffer = buffer,
      callback = function()
        vim.o.guicursor = "a:block-ProudCursorHidden"
      end,
    })
  end
  header.set_value(editable and (options.value or "") or (options.text or ""))
  return header
end

function M.pane_header_separator(parent_window, options)
  options = options or {}
  local parent = vim.api.nvim_win_get_config(parent_window)
  local width = math.max(1, parent.width or 1)
  local buffer = prepare_buffer(options.buffer_name or "proud://pane/separator")
  local line = string.rep("─", width)
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { line })
  vim.bo[buffer].modifiable = false
  vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
  vim.api.nvim_buf_set_extmark(buffer, namespace, 0, 0, {
    end_col = #line,
    hl_group = options.group or "ProudBorder",
  })
  local window = vim.api.nvim_open_win(buffer, false, {
    relative = "editor",
    row = (parent.row or 0) + (options.inside and 2 or 1),
    col = (parent.col or 0) + (options.inside and 1 or 0),
    width = width,
    height = 1,
    border = "none",
    style = "minimal",
    noautocmd = true,
    zindex = (parent.zindex or 50) + 1,
  })
  vim.wo[window].winhighlight = table.concat({
    "Normal:" .. (options.normal_group or "ProudBackground"),
    "NormalNC:" .. (options.normal_group or "ProudBackground"),
    "NormalFloat:" .. (options.normal_group or "ProudBackground"),
    "EndOfBuffer:ProudBorder",
  }, ",")
  vim.wo[window].number = false
  vim.wo[window].relativenumber = false
  vim.wo[window].signcolumn = "no"
  vim.wo[window].cursorline = false
  vim.wo[window].wrap = false
  return { window = window, buffer = buffer, render = function()
    if not vim.api.nvim_win_is_valid(parent_window) or not vim.api.nvim_win_is_valid(window) then
      return
    end
    local current_parent = vim.api.nvim_win_get_config(parent_window)
    local current_width = math.max(1, current_parent.width or 1)
    local line = string.rep("─", current_width)
    vim.bo[buffer].modifiable = true
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { line })
    vim.bo[buffer].modifiable = false
    vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
    vim.api.nvim_buf_set_extmark(buffer, namespace, 0, 0, {
      end_col = #line,
      hl_group = options.group or "ProudBorder",
    })
    vim.api.nvim_win_set_config(window, {
      relative = "editor",
      row = (current_parent.row or 0) + (options.inside and 2 or 1),
      col = (current_parent.col or 0) + (options.inside and 1 or 0),
      width = current_width,
      height = 1,
      border = "none",
      style = "minimal",
      zindex = (current_parent.zindex or 50) + 1,
    })
  end }
end

function M.button_style(options)
  options = options or {}
  return {
    selected_group = options.selected_group or "ProudAccent",
    item_group = options.item_group or "ProudMuted",
    selected_padding = options.selected_padding or 2,
    item_padding = options.item_padding or 1,
    height = math.max(1, math.floor(tonumber(options.height) or 1)),
  }
end

function M.button_layout(items, selected, width, options)
  items = items or {}
  selected = math.max(1, math.min(#items, math.floor(tonumber(selected) or 1)))
  width = math.max(1, math.floor(tonumber(width) or 1))
  local style = M.button_style(options)
  local visible = {}
  for index = 1, #items do
    table.insert(visible, index)
  end
  local function labels()
    local values = {}
    for _, index in ipairs(visible) do
      local item = items[index]
      local value = type(item) == "table" and (item.label or item.text) or item
      table.insert(values, tostring(value or ""))
    end
    return values
  end
  local function minimum_width(values)
    local total = math.max(0, #values - 1) + #values * 2
    for _, value in ipairs(values) do
      total = total + math.min(1, display_width(value))
    end
    return total
  end
  local values = labels()
  while #visible > 1 and minimum_width(values) > width do
    local remove_position
    local remove_distance = -1
    for position, index in ipairs(visible) do
      local distance = math.abs(index - selected)
      if distance > remove_distance then
        remove_distance = distance
        remove_position = position
      end
    end
    table.remove(visible, remove_position)
    values = labels()
  end

  local separator_width = #values > 1 and math.floor((width - #values * 3) / #values) < 3 and 1 or 2
  local target_labels = math.max(#values, width - math.max(0, #values - 1) * separator_width - #values * 2)
  local label_widths = {}
  local used = 0
  for index, value in ipairs(values) do
    label_widths[index] = math.min(1, display_width(value))
    used = used + label_widths[index]
  end
  while used < target_labels do
    local grew = false
    for index, value in ipairs(values) do
      if used >= target_labels then
        break
      end
      if label_widths[index] < display_width(value) then
        label_widths[index] = label_widths[index] + 1
        used = used + 1
        grew = true
      end
    end
    if not grew then
      break
    end
  end

  local segments = {}
  local highlights = {}
  local text = ""
  for position, value in ipairs(values) do
    local fitted = M.fit(value, label_widths[position]):gsub("%s+$", "")
    local is_selected = visible[position] == selected
    local selected_padding = string.rep(" ", style.selected_padding)
    local item_padding = string.rep(" ", style.item_padding)
    local segment = is_selected
      and (selected_padding .. fitted .. selected_padding)
      or (item_padding .. fitted .. item_padding)
    if position > 1 then
      text = text .. string.rep(" ", separator_width)
    end
    local start_col = #text
    text = text .. segment
    table.insert(highlights, {
      0,
      start_col,
      #text,
      is_selected and style.selected_group or style.item_group,
    })
  end
  text = M.fit(text, width)
  return {
    lines = { text },
    text = text,
    highlights = highlights,
    selected = selected,
  }
end

function M.selector_layout(items, selected, width, options)
  return M.button_layout(items, selected, width, options)
end

function M.open_selector_bar(options)
  options = options or {}
  local selected = math.max(1, math.min(#(options.items or {}), math.floor(tonumber(options.selected) or 1)))
  local width = math.max(1, math.floor(tonumber(options.width) or 1))
  local style = M.button_style(options)
  local height = style.height
  local buffer = prepare_buffer(options.buffer_name or "proud://selector")
  local function render()
    local view = M.button_layout(options.items, selected, width, options)
    M.render(buffer, { lines = { view.text }, highlights = view.highlights })
  end
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].modifiable = false
  local window = vim.api.nvim_open_win(buffer, false, {
    relative = "editor",
    row = math.max(0, math.floor(tonumber(options.row) or 0)),
    col = math.max(0, math.floor(tonumber(options.col) or 0)),
    width = width,
    height = height,
    border = "none",
    style = "minimal",
    focusable = false,
    noautocmd = true,
    zindex = options.zindex or 51,
  })
  vim.wo[window].winhighlight = table.concat({
    "Normal:ProudBackground",
    "NormalNC:ProudBackground",
    "NormalFloat:ProudBackground",
    "EndOfBuffer:ProudBackground",
  }, ",")
  vim.wo[window].number = false
  vim.wo[window].relativenumber = false
  vim.wo[window].signcolumn = "no"
  vim.wo[window].cursorline = false
  vim.wo[window].wrap = false
  vim.wo[window].linebreak = false
  render()
  return {
    buffer = buffer,
    window = window,
    get_selected = function()
      return selected
    end,
    resize = function()
      if not vim.api.nvim_win_is_valid(window) then
        return
      end
      local config = vim.api.nvim_win_get_config(window)
      local current_width = math.max(1, math.floor(tonumber(config.width) or width))
      width = current_width
      render()
    end,
    set_selected = function(value, notify)
      local next_value = math.max(1, math.min(#(options.items or {}), math.floor(tonumber(value) or 1)))
      if next_value == selected then
        return
      end
      selected = next_value
      render()
      if notify and options.on_change then
        options.on_change(selected, options.items[selected])
      end
    end,
  }
end

function M.set_title(buffer, title)
  vim.api.nvim_buf_set_name(buffer, title)
end

function M.open_tab(view, name)
  vim.cmd("tabnew")
  local window = vim.api.nvim_get_current_win()
  local buffer = prepare_buffer(name)
  vim.api.nvim_win_set_buf(window, buffer)
  decorate_window(window, buffer, name)
  M.render(buffer, view)
  return buffer, window
end

function M.open_surface(view, name, options)
  options = options or {}
  local buffer, window = M.open_tab(view, name)
  vim.b[buffer].proud_title = options.title or title_for(name)
  vim.wo[window].statusline = table.concat({
    "%#ProudAccent# PROUD ",
    "%#ProudBorder# ▎ ",
    "%#ProudBright# ",
    options.statusline or vim.b[buffer].proud_title,
    " ",
    "%#ProudBorder#▎",
    "%<",
    "%#ProudPanel#%=",
    "%#ProudMuted# Help available",
    "%#ProudPanel# ",
  })
  return buffer, window
end

function M.open_rounded_pair(views, options)
  options = options or {}
  vim.cmd("tabnew")
  local tabpage = vim.api.nvim_get_current_tabpage()
  local tab_initial_buffer = vim.api.nvim_get_current_buf()
  local backdrop = prepare_buffer(options.backdrop_name or "proud://surface/backdrop")
  local backdrop_window = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(backdrop_window, backdrop)
  decorate_window(backdrop_window, backdrop, options.backdrop_name or "proud://surface/backdrop", {
    title = options.title or "proud",
    statusline = options.statusline or options.title or "proud",
  })

  local list_buffer = prepare_buffer(options.list_name or "proud://prs/list")
  local preview_buffer = prepare_buffer(options.preview_name or "proud://prs/preview")
  local configured_layout = options.windows and M.configure(options.windows) or M.layout_config()
  local function geometry()
    return geometry_math.surface(vim.o.columns, vim.o.lines, configured_layout)
  end
  local initial_geometry = geometry()

  local function config(row, col, width, height, focusable, creating)
    return {
      relative = "editor",
      row = row,
      col = col,
      width = width,
      height = height,
      border = "rounded",
      focusable = focusable,
      style = "minimal",
      noautocmd = creating or nil,
    }
  end

  local list_window = vim.api.nvim_open_win(
    list_buffer,
    true,
    config(initial_geometry.row, initial_geometry.left_col, initial_geometry.left_width, initial_geometry.height, true, true)
  )
  local preview_window = vim.api.nvim_open_win(
    preview_buffer,
    false,
    config(initial_geometry.row, initial_geometry.right_col, initial_geometry.right_width, initial_geometry.height, true, true)
  )
  decorate_window(list_window, list_buffer, options.list_name or "proud://prs/list", {
    title = options.list_title or "pull requests",
    statusline = options.statusline or "pull requests",
    cursorline = false,
    hide_cursor = true,
    normal_group = "ProudBackground",
    normal_nc_group = "ProudBackground",
    float_group = "ProudBackground",
  })
  decorate_window(preview_window, preview_buffer, options.preview_name or "proud://prs/preview", {
    title = options.preview_title or "Preview",
    statusline = options.statusline or "Preview",
    cursorline = false,
    hide_cursor = false,
    normal_group = "ProudBackground",
    normal_nc_group = "ProudBackground",
    float_group = "ProudBackground",
    float_border = "ProudPreviewBorder",
    float_title = "ProudPreviewTitle",
  })
  vim.wo[preview_window].winhighlight = table.concat({
    "Normal:ProudBackground",
    "NormalNC:ProudBackground",
    "EndOfBuffer:ProudBorder",
    "StatusLine:ProudPanel",
    "StatusLineNC:ProudPanel",
    "TabLine:ProudPanel",
    "TabLineSel:ProudTabActive",
    "WinSeparator:ProudBorder",
    "NormalFloat:ProudBackground",
    "FloatBorder:ProudPreviewBorder",
    "FloatTitle:ProudPreviewTitle",
    "CursorLine:ProudSelection",
    "Cursor:ProudAccent",
    "lCursor:ProudAccent",
    "CursorIM:ProudAccent",
  }, ",")
  M.render(list_buffer, views.list or { lines = {} }, { top_pad = 2 })
  M.render(preview_buffer, views.preview or { lines = {} }, { top_pad = 2 })
  local headers = options.headers or {}
  local list_header = M.open_pane_header(list_window, vim.tbl_extend("force", {
    buffer_name = options.list_header_name or "proud://headers/list",
    title = "pull request filters",
    prompt = "PR > ",
    placeholder = "...",
    prompt_segments = {
      { text = "PR", group = "ProudAccentText" },
      { text = " > ", group = "ProudBorder" },
    },
    value_group = "ProudBright",
    placeholder_group = "ProudMuted",
    inside = true,
  }, headers.list or {}))
  local preview_header = M.open_pane_header(preview_window, vim.tbl_extend("force", {
    buffer_name = options.preview_header_name or "proud://headers/preview",
    title = "preview",
    text = "Preview",
    text_group = "ProudPreviewBorder",
    normal_group = "ProudBackground",
    border_group = "ProudPreviewBorder",
    focusable = false,
    inside = true,
  }, headers.preview or {}))
  local list_header_separator = M.pane_header_separator(list_window, {
    buffer_name = options.list_separator_name or "proud://headers/list-separator",
    group = "ProudBorder",
    inside = true,
  })
  local preview_header_separator = M.pane_header_separator(preview_window, {
    buffer_name = options.preview_separator_name or "proud://headers/preview-separator",
    group = "ProudBorder",
    inside = true,
  })
  local selector
  if options.selector then
    selector = M.open_selector_bar(vim.tbl_extend("force", {
      row = math.max(initial_geometry.top, initial_geometry.row - 2),
      col = initial_geometry.left_col,
      width = initial_geometry.available_width,
      buffer_name = "proud://selector",
    }, options.selector))
  end
  vim.api.nvim_set_current_win(list_window)

  local surface = {
    tabpage = tabpage,
    buffer = list_buffer,
    window = list_window,
    backdrop_window = backdrop_window,
    selector = selector,
    order = { "list", "preview" },
    panes = {
      list = {
        name = "list",
        buffer = list_buffer,
        window = list_window,
        header = list_header,
        header_separator = list_header_separator,
        width = vim.api.nvim_win_get_width(list_window),
      },
      preview = {
        name = "preview",
        buffer = preview_buffer,
        window = preview_window,
        header = preview_header,
        header_separator = preview_header_separator,
        width = vim.api.nvim_win_get_width(preview_window),
      },
    },
  }

  function surface.focus_preview()
    if not vim.api.nvim_win_is_valid(preview_window) then
      return false
    end
    vim.api.nvim_set_current_win(preview_window)
    vim.o.guicursor = "a:block-ProudAccent"
    local line_count = vim.api.nvim_buf_line_count(preview_buffer)
    local row = math.max(1, math.min(line_count, 3))
    pcall(vim.api.nvim_win_set_cursor, preview_window, { row, 0 })
    return true
  end

  function surface.focus_list()
    if not vim.api.nvim_win_is_valid(list_window) then
      return false
    end
    vim.api.nvim_set_current_win(list_window)
    vim.o.guicursor = "a:block-ProudCursorHidden"
    return true
  end

  function surface.resize()
    if not vim.api.nvim_tabpage_is_valid(tabpage) then
      return false
    end
    local next_geometry = geometry()
    vim.api.nvim_win_set_config(list_window, config(
      next_geometry.row,
      next_geometry.left_col,
      next_geometry.left_width,
      next_geometry.height,
      true
    ))
    vim.api.nvim_win_set_config(preview_window, config(
      next_geometry.row,
      next_geometry.right_col,
      next_geometry.right_width,
      next_geometry.height,
      false
    ))
    if list_header then
      list_header.resize()
    end
    if preview_header then
      preview_header.resize()
    end
    if list_header_separator then
      list_header_separator.render()
    end
    if preview_header_separator then
      preview_header_separator.render()
    end
    if selector then
      vim.api.nvim_win_set_config(selector.window, {
        relative = "editor",
        row = math.max(next_geometry.top, next_geometry.row - 2),
        col = next_geometry.left_col,
        width = next_geometry.available_width,
        height = 1,
        border = "none",
        style = "minimal",
        focusable = false,
        zindex = 51,
      })
      selector.resize()
    end
    surface.panes.list.width = next_geometry.left_width
    surface.panes.preview.width = next_geometry.right_width
    if options.on_resize then
      options.on_resize(surface)
    end
    return true
  end

  local owned_buffers = {
    tab_initial_buffer,
    backdrop,
    list_buffer,
    preview_buffer,
    list_header and list_header.buffer,
    preview_header and preview_header.buffer,
    list_header_separator and list_header_separator.buffer,
    preview_header_separator and preview_header_separator.buffer,
    selector and selector.buffer,
  }
  local lifecycle = M.create_scene_lifecycle({
    tabpage = tabpage,
    on_close = options.on_close,
    on_closed = options.on_closed,
  })
  local owned_windows = {
    backdrop_window,
    list_window,
    preview_window,
    list_header and list_header.window,
    preview_header and preview_header.window,
    list_header_separator and list_header_separator.window,
    preview_header_separator and preview_header_separator.window,
    selector and selector.window,
  }
  for _, buffer in ipairs(owned_buffers) do
    lifecycle.track_buffer(buffer)
  end
  for _, window in ipairs(owned_windows) do
    lifecycle.track_window(window)
  end
  vim.api.nvim_create_autocmd("VimResized", {
    group = lifecycle.group,
    callback = function()
      if vim.api.nvim_tabpage_is_valid(tabpage) then
        surface.resize()
      end
    end,
  })
  surface.lifecycle = lifecycle
  surface.close = lifecycle.close
  return surface
end

function M.open_split(view, name, direction)
  vim.cmd(direction == "horizontal" and "botright new" or "botright vnew")
  local window = vim.api.nvim_get_current_win()
  local buffer = prepare_buffer(name)
  vim.api.nvim_win_set_buf(window, buffer)
  decorate_window(window, buffer, name)
  M.render(buffer, view)
  return buffer, window
end

local calculate_widths = geometry_math.workspace_widths

function M.open_workspace(name, panes, options)
  options = options or {}
  vim.cmd("tabnew")
  local tab_initial_buffer = vim.api.nvim_get_current_buf()
  local workspace = {
    name = name,
    tabpage = vim.api.nvim_get_current_tabpage(),
    panes = {},
    order = {},
    options = options,
    owned_buffers = { tab_initial_buffer },
  }
  local weights = {}
  for _, pane in ipairs(panes) do
    table.insert(weights, pane.weight or 1)
  end
  local widths = calculate_widths(weights, vim.o.columns)
  workspace.widths = vim.deepcopy(widths)

  for index, pane in ipairs(panes) do
    local buffer_before = vim.api.nvim_get_current_buf()
    if index > 1 then
      vim.cmd("botright vnew")
      local split_buffer = vim.api.nvim_get_current_buf()
      if split_buffer ~= buffer_before then
        table.insert(workspace.owned_buffers, split_buffer)
      end
    end
    local window = vim.api.nvim_get_current_win()
    local buffer_name = pane.buffer_name or (name .. "/" .. pane.name)
    local buffer = prepare_buffer(buffer_name)
    vim.api.nvim_win_set_buf(window, buffer)
    decorate_window(window, buffer, buffer_name, {
      title = pane.title or options.title,
      statusline = options.statusline,
    })
    workspace.panes[pane.name] = {
      name = pane.name,
      buffer_name = buffer_name,
      buffer = buffer,
      window = window,
      weight = pane.weight or 1,
      width = widths[index],
      last_view = vim.deepcopy(pane.view or { lines = {} }),
    }
    table.insert(workspace.order, pane.name)
    table.insert(workspace.owned_buffers, buffer)
    M.render(buffer, M.fit_view(pane.view or { lines = {} }, widths[index]))
    sync_text_frame(workspace.panes[pane.name], pane.view)
  end

  for index = 1, #panes - 1 do
    local pane = workspace.panes[panes[index].name]
    pcall(vim.api.nvim_win_set_width, pane.window, widths[index])
  end
  local focus = options.focus or panes[1].name
  if workspace.panes[focus] then
    vim.api.nvim_set_current_win(workspace.panes[focus].window)
  end

  local user_on_close = options.on_close
  local lifecycle = M.create_scene_lifecycle({
    tabpage = workspace.tabpage,
    on_close = function(scene)
      close_text_frames(workspace)
      if user_on_close then
        pcall(user_on_close, scene)
      end
    end,
    on_closed = options.on_closed,
  })
  for _, buffer in ipairs(workspace.owned_buffers) do
    lifecycle.track_buffer(buffer)
  end
  for _, pane in pairs(workspace.panes) do
    lifecycle.track_window(pane.window)
  end
  workspace.lifecycle = lifecycle
  workspace.close = lifecycle.close
  vim.api.nvim_create_autocmd("VimResized", {
    group = lifecycle.group,
    callback = function()
      M.resize_workspace(workspace)
    end,
  })
  return workspace
end

function M.resize_workspace(workspace)
  if not vim.api.nvim_tabpage_is_valid(workspace.tabpage) then
    return
  end
  local weights = {}
  for _, pane_name in ipairs(workspace.order) do
    table.insert(weights, workspace.panes[pane_name].weight)
  end
  local widths = calculate_widths(weights, vim.o.columns)
  workspace.widths = vim.deepcopy(widths)
  for index, pane_name in ipairs(workspace.order) do
    local pane = workspace.panes[pane_name]
    pane.width = widths[index]
    if index < #workspace.order then
      pcall(vim.api.nvim_win_set_width, pane.window, widths[index])
    end
  end
  for index, pane_name in ipairs(workspace.order) do
    local pane = workspace.panes[pane_name]
    if pane.last_view and vim.api.nvim_buf_is_valid(pane.buffer) then
      M.render(pane.buffer, M.fit_view(pane.last_view, widths[index]))
      sync_text_frame(pane, pane.last_view)
    end
  end
  if workspace.options.on_resize then
    workspace.options.on_resize(workspace)
  end
end

function M.render_workspace(workspace, views)
  for pane_name, pane in pairs(workspace.panes) do
    local view = views[pane_name]
    if view and vim.api.nvim_buf_is_valid(pane.buffer) then
      local width = vim.api.nvim_win_is_valid(pane.window)
        and vim.api.nvim_win_get_width(pane.window)
        or pane.width
      pane.last_view = vim.deepcopy(view)
      M.render(pane.buffer, M.fit_view(view, width))
      sync_text_frame(pane, view)
    end
  end
end

function M.workspace_buffer(workspace, pane_name)
  local pane = workspace.panes[pane_name]
  return pane and pane.buffer or nil
end

function M.workspace_window(workspace, pane_name)
  local pane = workspace.panes[pane_name]
  return pane and pane.window or nil
end

function M.focus_workspace_pane(workspace, pane_name)
  local pane = workspace.panes[pane_name]
  if pane and vim.api.nvim_win_is_valid(pane.window) then
    vim.api.nvim_set_current_win(pane.window)
    return true
  end
  return false
end

function M.close_workspace(workspace)
  if not workspace then
    return
  end
  if workspace.close then
    workspace.close()
  else
    if vim.api.nvim_tabpage_is_valid(workspace.tabpage) then
      vim.api.nvim_set_current_tabpage(workspace.tabpage)
      vim.cmd("tabclose")
    end
    delete_owned_buffers(workspace.owned_buffers)
  end
end

function M.open_float(view, name, options)
  options = options or {}
  vim.o.guicursor = default_guicursor
  local width = options.width or math.min(vim.o.columns - 8, 132)
  local height = options.height or math.min(vim.o.lines - 8, 34)
  local row = options.row or math.floor((vim.o.lines - height) / 2)
  local col = options.col or math.floor((vim.o.columns - width) / 2)
  local buffer = prepare_buffer(name)
  local window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
  })
  vim.wo[window].winhighlight = "NormalFloat:ProudBackground,FloatBorder:ProudAccent"
  vim.wo[window].wrap = false
  vim.wo[window].cursorline = true
  vim.b[buffer].proud_title = title_for(name)
  vim.wo[window].statusline = "%#ProudAccent# PROUD %#ProudPanel# Help available"
  M.render(buffer, view)
  local header = options.header and M.open_pane_header(window, options.header) or nil
  return buffer, window, header
end

local function reveal_window(window, first_row, last_row, column, reserved_rows)
  reserved_rows = math.max(0, math.floor(tonumber(reserved_rows) or 0))
  local height = math.max(1, vim.api.nvim_win_get_height(window))
  local visible_height = math.max(1, height - reserved_rows)
  local line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(window))
  local view = vim.api.nvim_win_call(window, function()
    return vim.fn.winsaveview()
  end)
  local maximum_topline = first_row - reserved_rows
  local minimum_topline = last_row - reserved_rows - visible_height + 1
  local topline = math.max(minimum_topline, math.min(view.topline, maximum_topline))
  topline = math.max(1, math.min(topline, math.max(1, line_count - height + 1)))
  vim.api.nvim_win_call(window, function()
    vim.fn.winrestview({
      topline = topline,
      lnum = first_row,
      col = column,
      leftcol = view.leftcol,
    })
  end)
end

function M.set_cursor(buffer, row, col, visible_through_row, options)
  options = options or {}
  local line_count = vim.api.nvim_buf_line_count(buffer)
  row = math.max(1, math.min(line_count, row))
  local line = vim.api.nvim_buf_get_lines(buffer, row - 1, row, false)[1] or ""
  col = math.max(0, math.min(col or 0, #line))
  for _, window in ipairs(vim.fn.win_findbuf(buffer)) do
    pcall(vim.api.nvim_win_set_cursor, window, { row, col })
    if visible_through_row then
      reveal_window(window, row, math.min(line_count, visible_through_row), col, options.reserved_rows)
    end
  end
end

function M.map(buffer, mode, lhs, rhs, description)
  vim.keymap.set(mode, lhs, rhs, {
    buffer = buffer,
    silent = false,
    nowait = true,
    desc = description,
  })
end

function M.map_workspace(workspace, mode, lhs, rhs, description)
  for _, pane_name in ipairs(workspace.order) do
    M.map(workspace.panes[pane_name].buffer, mode, lhs, rhs, description)
  end
end

function M.feedback(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "proud" })
end

return M
