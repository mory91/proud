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

local function status_group(status)
  return status == "A" and "ProudSuccessText"
    or status == "D" and "ProudDangerText"
    or "ProudAccentText"
end

-- Byte padding, matching string.format's %-Ns columns.
local function pad(value, width)
  return string.rep(" ", math.max(0, width - #value))
end

local function render_header(v, state)
  v:line({ "Compare", "ProudAccentText" }, "  ", { state.mode, "ProudAccentText" }, ", from merge base")
  v:line(
    { "base", "ProudMuted" }, "  ", { state.base, "ProudAccentText" }, pad(state.base, 28),
    " ", { "head", "ProudMuted" }, "  ", { state.head, "ProudSuccessText" }
  )
  v:line(
    "↑" .. state.ahead .. " ", { "ahead", "ProudSuccessText" },
    "  · ↓" .. state.behind .. " ", { "behind", "ProudWarning" },
    "  · " .. state.notes .. " ", { "local notes", "ProudMuted" }
  )
  v:blank()
end

local function render_changes(v, state)
  local additions, deletions = totals(state.files)
  v:line({ "Commits", "ProudAccentText" }, "  " .. #state.commits)
  if state.loading then
    v:line("Loading comparison...")
  end
  for _, commit in ipairs(state.commits) do
    v:line({ commit.sha or "", "ProudAccentText" }, "  " .. (commit.message or ""))
  end
  v:blank()
  v:line({ "Files", "ProudAccentText" }, ("  %d  +%d  -%d"):format(#state.files, additions, deletions))
  for file_index, file in ipairs(state.files) do
    local status = file.status or "M"
    local added = "+" .. tostring(file.additions or 0)
    local deleted = "-" .. tostring(file.deletions or 0)
    local notes = file.notes and file.notes > 0 and ("◇" .. file.notes) or nil
    if file_index == 1 then
      v:line(
        { status, "ProudAccentText" }, " ", { file.path, "ProudBright" }, pad(file.path, 36),
        " ", { added, "ProudSuccessText" }, " ", { deleted, "ProudDangerText" },
        notes and " " or nil, notes and { notes, "ProudWarning" } or nil
      )
    else
      local row = v:line(("%s %-36s %s %s%s"):format(status, file.path, added, deleted, notes and (" " .. notes) or ""))
      v:mark(row, 0, #v.lines[row + 1], status_group(file.status))
    end
  end
end

local function render_footer(v, state)
  v:blank()
  v:line({ "Open a pull request", "ProudAccentText" }, " or inspect this ", { "local branch comparison", "ProudSuccessText" }, ".")
  v:line(state.notes .. " ", { "local note", "ProudMuted" }, " stays local until you open a PR")
end

function M.render(state)
  local v = ui.view.new()
  render_header(v, state)
  render_changes(v, state)
  render_footer(v, state)
  return v:build()
end

function M.render_panes(state)
  local summary = ui.view.new()
  render_header(summary, state)
  summary:blank()
  render_footer(summary, state)
  local changes = ui.view.new()
  render_changes(changes, state)
  return { summary = summary:build(), changes = changes:build() }
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
