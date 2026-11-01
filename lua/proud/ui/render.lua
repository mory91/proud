local ui_text = require("proud.ui.text")

local M = {}

M.namespace = vim.api.nvim_create_namespace("proud")
local namespace = M.namespace

-- Views carry highlights in one of two formats:
--   highlight_format = "flat": r, s, e, group repeated in one array
--     (what proud.ui.view's builder emits; preferred)
--   otherwise keyed: { line = r, start_col = s, end_col = e, group = g },
--     where a missing start_col means 0 and a missing end_col the line end.
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

-- Buffer lines cannot contain newlines; replace them with spaces.
local function single_line(value)
  value = tostring(value)
  if value:find("[\r\n]") then
    value = (value:gsub("\r\n", "\n"):gsub("[\r\n]", " "))
  end
  return value
end

local function set_mark(buffer, lines, row, start_col, end_col, group)
  local line = lines[row + 1] or ""
  start_col = math.max(0, math.min(start_col, #line))
  end_col = math.max(start_col, math.min(end_col, #line))
  if end_col > start_col then
    vim.api.nvim_buf_set_extmark(buffer, namespace, row, start_col, {
      end_col = end_col,
      hl_group = group,
    })
  end
end

-- Writes a view into `buffer`. options.top_pad reserves blank rows above
-- the content (e.g. for in-pane headers); highlight rows are offset while
-- placing them, so the view itself is never copied or modified.
function M.render(buffer, view, options)
  options = options or {}
  local offset = math.max(0, math.floor(tonumber(options.top_pad) or 0))
  local source = view.lines or {}
  local lines = {}
  if offset > 0 then
    local pad = string.rep(" ", ui_text.display_width(tostring(source[1] or "")))
    for index = 1, offset do
      lines[index] = pad
    end
  end
  for index = 1, #source do
    lines[offset + index] = single_line(source[index])
  end
  local highlights = view.highlights or {}
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
  if view.highlight_format == "flat" then
    for index = 1, #highlights, 4 do
      set_mark(buffer, lines, highlights[index] + offset, highlights[index + 1], highlights[index + 2], highlights[index + 3])
    end
  else
    for _, item in ipairs(highlights) do
      local row = item.line + offset
      local line = lines[row + 1] or ""
      set_mark(buffer, lines, row, item.start_col or 0, item.end_col or #line, item.group)
    end
  end
  local virtual = view.virtual or {}
  for index = 1, #virtual, 3 do
    local row = virtual[index] + offset
    if row < #lines then
      vim.api.nvim_buf_set_extmark(buffer, namespace, row, 0, {
        virt_text = { { virtual[index + 1], virtual[index + 2] } },
        virt_text_pos = "eol",
      })
    end
  end
  vim.bo[buffer].modifiable = false
end

return M
