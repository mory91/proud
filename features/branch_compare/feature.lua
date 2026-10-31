local ui = require("proud.ui")
local keymap = require("proud.keymap")

local M = {}

local function totals(files)
  local additions = 0
  local deletions = 0
  for _, file in ipairs(files) do
    additions = additions + (file.additions or 0)
    deletions = deletions + (file.deletions or 0)
  end
  return additions, deletions
end

local add_span = ui.view.span

function M.create(input)
  input = input or {}
  return {
    base = input.base or "main",
    head = input.head or "feature",
    ahead = input.ahead or 0,
    behind = input.behind or 0,
    commits = input.commits or {},
    files = input.files or {},
    notes = input.notes or 0,
    mode = input.mode or "three-dot",
    loading = input.loading == true,
  }
end

function M.hydrate(state, input)
  input = input or {}
  local swapped = input.base ~= nil
    and input.head ~= nil
    and state.base == input.head
    and state.head == input.base
  state.ahead = swapped and (input.behind or 0) or (input.ahead or 0)
  state.behind = swapped and (input.ahead or 0) or (input.behind or 0)
  state.commits = input.commits or {}
  state.files = input.files or {}
  state.notes = input.notes or 0
  if input.mode then
    state.mode = input.mode
  end
  state.loading = false
  if state.refresh then
    state.refresh()
  end
  return state
end

function M.swap(state)
  state.base, state.head = state.head, state.base
  state.ahead, state.behind = state.behind, state.ahead
end

function M.toggle_mode(state)
  state.mode = state.mode == "three-dot" and "two-dot" or "three-dot"
end

function M.render(state)
  local lines = {}
  local highlights = {}
  local additions, deletions = totals(state.files)
  table.insert(lines, "Compare  " .. state.mode .. ", from merge base")
  table.insert(lines, ("base  %-28s head  %s"):format(state.base, state.head))
  table.insert(lines, ("↑%d ahead  · ↓%d behind  · %s"):format(state.ahead, state.behind, state.notes .. " local notes"))
  table.insert(lines, "")
  table.insert(lines, "Commits  " .. #state.commits)
  if state.loading then
    table.insert(lines, "Loading comparison...")
  end
  for _, commit in ipairs(state.commits) do
    table.insert(lines, ("%s  %s"):format(commit.sha or "", commit.message or ""))
    add_span(lines, highlights, #lines - 1, commit.sha or "", "ProudAccentText")
  end
  table.insert(lines, "")
  table.insert(lines, ("Files  %d  +%d  -%d"):format(#state.files, additions, deletions))
  for file_index, file in ipairs(state.files) do
    table.insert(lines, ("%s %-36s +%d -%d%s"):format(
      file.status or "M",
      file.path,
      file.additions or 0,
      file.deletions or 0,
      file.notes and file.notes > 0 and (" ◇" .. file.notes) or ""
    ))
    local line = #lines - 1
    if file_index == 1 then
      add_span(lines, highlights, line, file.status or "M", "ProudAccentText")
      add_span(lines, highlights, line, file.path, "ProudBright")
      add_span(lines, highlights, line, "+" .. tostring(file.additions or 0), "ProudSuccessText")
      add_span(lines, highlights, line, "-" .. tostring(file.deletions or 0), "ProudDangerText")
      if file.notes and file.notes > 0 then
        add_span(lines, highlights, line, "◇" .. tostring(file.notes), "ProudWarning")
      end
    else
      local status_group = file.status == "A" and "ProudSuccessText"
        or file.status == "D" and "ProudDangerText"
        or "ProudAccentText"
      table.insert(highlights, {
        line = line,
        start_col = 0,
        end_col = #lines[#lines],
        group = status_group,
      })
    end
  end
  table.insert(lines, "")
  table.insert(lines, "Open a pull request or inspect this local branch comparison.")
  table.insert(lines, state.notes .. " local note stays local until you open a PR")
  add_span(lines, highlights, 0, "Compare", "ProudAccentText")
  add_span(lines, highlights, 0, state.mode, "ProudAccentText")
  add_span(lines, highlights, 1, "base", "ProudMuted")
  add_span(lines, highlights, 1, state.base, "ProudAccentText")
  add_span(lines, highlights, 1, "head", "ProudMuted")
  add_span(lines, highlights, 1, state.head, "ProudSuccessText")
  add_span(lines, highlights, 2, "ahead", "ProudSuccessText")
  add_span(lines, highlights, 2, "behind", "ProudWarning")
  add_span(lines, highlights, 2, "local notes", "ProudMuted")
  add_span(lines, highlights, 4, "Commits", "ProudAccentText")
  add_span(lines, highlights, 6 + #state.commits, "Files", "ProudAccentText")
  add_span(lines, highlights, #lines - 2, "Open a pull request", "ProudAccentText")
  add_span(lines, highlights, #lines - 2, "local branch comparison", "ProudSuccessText")
  add_span(lines, highlights, #lines - 1, "local note", "ProudMuted")
  return { lines = lines, highlights = highlights }
end

function M.render_panes(state)
  local combined = M.render(state)
  local function highlights_for(lines, first, last, offset)
    local values = {}
    for _, item in ipairs(combined.highlights) do
      if item.line >= first and item.line <= last then
        table.insert(values, {
          line = item.line - offset,
          start_col = item.start_col,
          end_col = item.end_col,
          group = item.group,
        })
      end
    end
    return values
  end
  local summary = {
    lines = {
      combined.lines[1],
      combined.lines[2],
      combined.lines[3],
      combined.lines[4],
      "",
      combined.lines[#combined.lines - 2],
      combined.lines[#combined.lines - 1],
      combined.lines[#combined.lines],
    },
    highlights = highlights_for(combined.lines, 0, 2, 0),
  }
  add_span(summary.lines, summary.highlights, 6, "Open a pull request", "ProudAccentText")
  add_span(summary.lines, summary.highlights, 7, "local note", "ProudMuted")
  local changes = { lines = {}, highlights = {} }
  for index = 5, #combined.lines - 3 do
    table.insert(changes.lines, combined.lines[index])
  end
  changes.highlights = highlights_for(combined.lines, 4, #combined.lines - 4, 4)
  return { summary = summary, changes = changes }
end

function M.attach(buffer, state, options)
  options = options or {}
  local function refresh()
    ui.render_workspace(options.workspace, M.render_panes(state))
  end
  state.refresh = refresh
  keymap.map(buffer, "n", "swap_branches", function()
    M.swap(state)
    refresh()
  end, "Swap base and head")
  keymap.map(buffer, "n", "toggle_compare_mode", function()
    M.toggle_mode(state)
    refresh()
  end, "Toggle compare mode")
  keymap.map(buffer, "n", "open_pull_request", options.on_open_pr or function() end, "Open pull request")
  keymap.bind_common_workspace(options.workspace, {
    on_quit = options.on_quit or function()
      ui.close_workspace(options.workspace)
    end,
  })
  refresh()
end

function M.open(state, options)
  local name = "proud://compare/" .. state.base .. "..." .. state.head
  local panes = M.render_panes(state)
  local workspace = ui.open_workspace(name, {
    {
      name = "summary",
      buffer_name = name .. "/summary",
      title = "compare  " .. state.base .. "..." .. state.head,
      view = panes.summary,
      weight = 0.36,
    },
    {
      name = "changes",
      buffer_name = name .. "/changes",
      title = "compare  " .. state.base .. "..." .. state.head,
      view = panes.changes,
      weight = 0.64,
    },
  }, {
    focus = "summary",
    title = "compare  " .. state.base .. "..." .. state.head,
    statusline = "compare  " .. state.base .. "..." .. state.head,
    on_resize = function()
      if state.refresh then
        state.refresh()
      end
    end,
  })
  state.workspace = workspace
  local buffer = ui.workspace_buffer(workspace, "summary")
  M.attach(buffer, state, vim.tbl_extend("force", options or {}, { workspace = workspace }))
  return buffer
end

return M
