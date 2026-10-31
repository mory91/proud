local ui_text = require("proud.ui.text")

local M = {}

M.namespace = vim.api.nvim_create_namespace("proud")
local namespace = M.namespace

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

-- Normalizes a view's lines to strings. Rows are intentionally not clipped:
-- native horizontal scrolling reveals content past the pane width. The
-- width argument is accepted for API compatibility and ignored.
function M.fit_view(view, _width)
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
  local row_width = ui_text.display_width((view.lines or {})[1] or "")
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

return M
