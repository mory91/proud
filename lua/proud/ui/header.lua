local ui_float = require("proud.ui.float")
local ui_render = require("proud.ui.render")
local ui_text = require("proud.ui.text")
local ui_window = require("proud.ui.window")

local M = {}

local namespace = ui_render.namespace

local function header_mark(buffer, start_col, end_col, group)
  if end_col > start_col then
    vim.api.nvim_buf_set_extmark(buffer, namespace, 0, start_col, {
      end_col = end_col,
      hl_group = group,
    })
  end
end

function M.open(parent_window, options)
  options = options or {}
  local parent = vim.api.nvim_win_get_config(parent_window)
  local width = math.max(1, parent.width or 1)
  local function current_width()
    if vim.api.nvim_win_is_valid(parent_window) then
      return math.max(1, vim.api.nvim_win_get_config(parent_window).width or 1)
    end
    return width
  end
  local editable = options.editable or options.prompt ~= nil
  local buffer = ui_window.buffer(options.buffer_name or "proud://pane/header", {
    bo = { buftype = editable and "prompt" or "nofile", modifiable = editable },
  })
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
  local prompt = editable and tostring(options.prompt or "") or ""
  if editable then
    vim.fn.prompt_setprompt(buffer, prompt)
  end
  local frame = ui_float.create(buffer, {
    enter = editable and options.focusable ~= false,
    placement = ui_float.anchored(
      parent_window,
      options.inside and { row = 1, col = 1 } or { row = -1, clamp_row = true }
    ),
  })
  local window = frame.window
  local normal_group = options.normal_group or "ProudBackground"
  ui_window.winhighlight(window, ui_window.cursor_groups({
    Normal = normal_group,
    NormalNC = normal_group,
    NormalFloat = normal_group,
    FloatBorder = options.border_group or "ProudBorder",
    Prompt = options.prompt_group or "ProudAccentText",
    EndOfBuffer = "ProudBorder",
  }, options.cursor_group or "ProudAccent"))
  ui_window.options(window)
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
    local text = ui_text.fit(options.text or "", current_width())
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
      vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { ui_text.fit(value, current_width()) })
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
        vim.o.guicursor = ui_window.default_guicursor
        if start_insert then
          vim.cmd("startinsert!")
        end
      end
    end
  end

  function header.resize()
    if frame.reposition() then
      header.render()
    end
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

function M.separator(parent_window, options)
  options = options or {}
  local parent = vim.api.nvim_win_get_config(parent_window)
  local width = math.max(1, parent.width or 1)
  local buffer = ui_window.buffer(options.buffer_name or "proud://pane/separator")
  local line = string.rep("─", width)
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { line })
  vim.bo[buffer].modifiable = false
  vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
  vim.api.nvim_buf_set_extmark(buffer, namespace, 0, 0, {
    end_col = #line,
    hl_group = options.group or "ProudBorder",
  })
  local frame = ui_float.create(buffer, {
    placement = ui_float.anchored(parent_window, {
      row = options.inside and 2 or 1,
      col = options.inside and 1 or 0,
    }),
  })
  local window = frame.window
  local normal_group = options.normal_group or "ProudBackground"
  ui_window.winhighlight(window, {
    Normal = normal_group,
    NormalNC = normal_group,
    NormalFloat = normal_group,
    EndOfBuffer = "ProudBorder",
  })
  ui_window.options(window)
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
    frame.reposition()
  end }
end

return M
