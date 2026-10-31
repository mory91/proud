local M = {}

local function parse_header(path)
  return path:gsub("^a/", ""):gsub("^b/", "")
end

function M.parse_patch(patch)
  local files = {}
  local current
  local old_line
  local new_line
  local in_hunk = false

  for _, raw in ipairs(vim.split(patch or "", "\n", { plain = true })) do
    if raw:match("^diff %-%-git ") then
      local old_path, new_path = raw:match("^diff %-%-git a/(.+) b/(.+)$")
      current = {
        path = parse_header(new_path or old_path or "unknown"),
        old_path = parse_header(old_path or new_path or "unknown"),
        lines = {},
        additions = 0,
        deletions = 0,
      }
      table.insert(files, current)
      in_hunk = false
    elseif current and raw:match("^@@ ") then
      local old_start, new_start = raw:match("^@@ %-(%d+),?%d* %+(%d+),?%d* @@")
      old_line = tonumber(old_start) or 1
      new_line = tonumber(new_start) or 1
      in_hunk = true
      table.insert(current.lines, {
        kind = "hunk",
        text = raw,
      })
    elseif in_hunk and current then
      local prefix = raw:sub(1, 1)
      local text = raw:sub(2)
      if prefix == "+" then
        table.insert(current.lines, {
          kind = "add",
          text = text,
          new_line = new_line,
        })
        current.additions = current.additions + 1
        new_line = new_line + 1
      elseif prefix == "-" then
        table.insert(current.lines, {
          kind = "delete",
          text = text,
          old_line = old_line,
        })
        current.deletions = current.deletions + 1
        old_line = old_line + 1
      elseif prefix == " " or raw == "" then
        table.insert(current.lines, {
          kind = "context",
          text = text,
          old_line = old_line,
          new_line = new_line,
        })
        old_line = old_line + 1
        new_line = new_line + 1
      elseif raw:match("^%-%-%- ") or raw:match("^%+%+%+ ") then
        table.insert(current.lines, {
          kind = "meta",
          text = raw,
        })
      end
    end
  end

  return files
end

function M.split_rows(file)
  local rows = {}
  local lines = file.lines or {}
  for _, line in ipairs(lines) do
    if line.kind == "delete" then
      table.insert(rows, { kind = "pair", left = line })
    elseif line.kind == "add" then
      table.insert(rows, { kind = "pair", right = line })
    else
      table.insert(rows, {
        kind = line.kind,
        left = line,
        right = line,
      })
    end
  end
  return rows
end

function M.file_rows(file, source)
  if type(source) == "string" then
    source = vim.split(source, "\n", { plain = true })
  end
  if type(source) ~= "table" or #source == 0 then
    return vim.deepcopy(file.lines or {})
  end

  local additions = {}
  local old_lines = {}
  local deletions = {}
  local lines = file.lines or {}
  for index, line in ipairs(lines) do
    if line.kind == "add" and line.new_line then
      additions[line.new_line] = line
    elseif line.kind == "context" and line.new_line then
      old_lines[line.new_line] = line.old_line
    elseif line.kind == "delete" then
      local anchor = #source + 1
      for next_index = index + 1, #lines do
        if lines[next_index].new_line then
          anchor = lines[next_index].new_line
          break
        end
      end
      table.insert(deletions, { line = line, anchor = anchor })
    end
  end

  local rows = {}
  local deletion_index = 1
  for number = 1, #source do
    while deletion_index <= #deletions and deletions[deletion_index].anchor <= number do
      local deleted = deletions[deletion_index].line
      table.insert(rows, {
        kind = "delete",
        text = deleted.text or "",
        old_line = deleted.old_line,
      })
      deletion_index = deletion_index + 1
    end
    local added = additions[number]
    table.insert(rows, {
      kind = added and "add" or "context",
      text = source[number] or "",
      old_line = old_lines[number],
      new_line = number,
    })
  end
  while deletion_index <= #deletions do
    local deleted = deletions[deletion_index].line
    table.insert(rows, {
      kind = "delete",
      text = deleted.text or "",
      old_line = deleted.old_line,
    })
    deletion_index = deletion_index + 1
  end
  return rows
end

function M.counts(files)
  local additions = 0
  local deletions = 0
  for _, file in ipairs(files) do
    additions = additions + file.additions
    deletions = deletions + file.deletions
  end
  return additions, deletions
end

return M
