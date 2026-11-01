local session = require("proud.session")

local scene = vim.env.PROUD_COLOR_SCENE or ""

local expectations = {
  browser = {
    { pane = "list", needle = "#482", group = "ProudAccentText" },
    { pane = "list", needle = "Add retry backoff", group = "ProudBright" },
    { pane = "list", needle = "●", group = "ProudSuccessText" },
    { pane = "list", needle = "sara-k", group = "ProudMuted" },
    { pane = "list", needle = "changes requested", group = "ProudWarning" },
    { pane = "list", needle = "+134", group = "ProudSuccessText" },
    { pane = "list", needle = "-17", group = "ProudDangerText" },
    { pane = "list", needle = "3 threads", group = "ProudWarning" },
    { pane = "list", needle = "▌", group = "ProudAccentText" },
    { pane = "preview", needle = "#482", group = "ProudAccentText" },
    { pane = "preview", needle = "+134", group = "ProudSuccessText" },
    { pane = "preview", needle = "-17", group = "ProudDangerText" },
    { pane = "preview", needle = "feat/task-retry-backoff", group = "ProudAccentText" },
    { pane = "preview", needle = "Reviewers", group = "ProudMuted" },
  },
  overview = {
    { pane = "sidebar", needle = "Files", group = "ProudBright" },
    { pane = "sidebar", needle = "5 · 1 of 5 viewed", group = "ProudMuted" },
    { pane = "sidebar", needle = "packages/runner/src", group = "ProudMuted" },
    { pane = "sidebar", needle = "retry.ts", group = "ProudBright" },
    { pane = "sidebar", needle = "+48", group = "ProudSuccessText" },
    { pane = "sidebar", needle = "-12", group = "ProudDangerText" },
    { pane = "sidebar", needle = "◆2", group = "ProudWarning" },
    { pane = "sidebar", needle = "viewed", group = "ProudSuccessText" },
    { pane = "sidebar", needle = "a3f91c2", group = "ProudAccentText" },
    { pane = "sidebar", needle = "Use config fo", group = "ProudBright" },
    { pane = "sidebar", needle = "4 of 5 passing", group = "ProudMuted" },
    { pane = "sidebar", needle = "lint", group = "ProudBright" },
    { pane = "sidebar", needle = "18s", group = "ProudMuted" },
    { pane = "sidebar", needle = "e2e / robot-studio", group = "ProudBright" },
    { pane = "sidebar", needle = "6m 40s", group = "ProudMuted" },
    { pane = "sidebar", needle = "✓", group = "ProudSuccessText" },
    { pane = "sidebar", needle = "✗", group = "ProudDangerText" },
    { pane = "details", needle = "Add retry backoff", group = "ProudBright" },
    { pane = "details", needle = "Open", group = "ProudSuccessText" },
    { pane = "details", needle = "feat/task-retry-backoff", group = "ProudAccentText" },
    { pane = "details", needle = "Description", group = "ProudMuted" },
    { pane = "details", needle = "Conversation", group = "ProudMuted" },
    { pane = "details", needle = "dev-lee", group = "ProudAccentText" },
    { pane = "details", needle = "change requested", group = "ProudWarning" },
  },
  single = {
    { pane = "winbar", needle = "main", group = "ProudAccentText" },
    { pane = "winbar", needle = "feat/task-retry-backoff", group = "ProudSuccessText" },
    { pane = "winbar", needle = "packages/runner/src/task/retry.ts", group = "ProudMuted" },
    { pane = "winbar", needle = "[+", group = "ProudAccentText" },
    { pane = "code", needle = "const delay", group = "ProudAdd" },
    { pane = "code", needle = "await sleep(1000)", group = "ProudDelete" },
    { pane = "code", needle = "◆", group = "ProudWarning" },
  },
  compare = {
    { pane = "summary", needle = "Compare", group = "ProudAccentText" },
    { pane = "summary", needle = "three-dot", group = "ProudAccentText" },
    { pane = "summary", needle = "main", group = "ProudAccentText" },
    { pane = "summary", needle = "feat/monitor-diffs", group = "ProudSuccessText" },
    { pane = "summary", needle = "ahead", group = "ProudSuccessText" },
    { pane = "summary", needle = "behind", group = "ProudWarning" },
    { pane = "summary", needle = "local note", group = "ProudMuted" },
    { pane = "changes", needle = "Commits", group = "ProudAccentText" },
    { pane = "changes", needle = "9a7d3f0", group = "ProudAccentText" },
    { pane = "changes", needle = "Files", group = "ProudAccentText" },
    { pane = "changes", needle = "M monitor/src/diff.ts", group = "ProudAccentText" },
    { pane = "changes", needle = "+44", group = "ProudSuccessText" },
    { pane = "changes", needle = "-22", group = "ProudDangerText" },
    { pane = "changes", needle = "◇1", group = "ProudWarning" },
  },
  help = {
    { pane = "bindings", needle = "Global", group = "ProudAccentText" },
    { pane = "bindings", needle = "j", group = "ProudBright" },
    { pane = "bindings", needle = "Select the next pull request", group = "ProudMuted" },
    { pane = "commands", needle = "Commands", group = "ProudAccentText" },
    { pane = "commands", needle = ":Proud prs", group = "ProudBright" },
    { pane = "commands", needle = "list pull requests", group = "ProudMuted" },
    { pane = "runtime", needle = "Runtime", group = "ProudAccentText" },
    { pane = "runtime", needle = "GitHub auth", group = "ProudAccentText" },
    { pane = "runtime", needle = "validates and reuses a token", group = "ProudMuted" },
    { pane = "runtime", needle = "independent panes", group = "ProudSuccessText" },
  },
  review = {
    { pane = "decisions", needle = "Review", group = "ProudBright" },
    { pane = "decisions", needle = "482", group = "ProudAccentText" },
    { pane = "decisions", needle = "Comment", group = "ProudAccent" },
    { pane = "decisions", needle = "Approve", group = "ProudMuted" },
    { pane = "decisions", needle = "Submit review", group = "ProudAccentText" },
    { pane = "body", needle = "Use exponential", group = "ProudBright" },
  },
}

local state = scene == "help" and session.help or session.current and session.current.state
local workspace = state and (state.workspace or state.surface)
local namespace = vim.api.nvim_get_namespaces().proud
local card_namespace = vim.api.nvim_get_namespaces().proud_conversation_cards

local function covers(mark, row, column)
  local detail = mark[4] or {}
  local start_col = detail.start_col or 0
  local end_col = detail.end_col or math.huge
  return mark[2] == row and start_col <= column and end_col > column
end

-- True when the code window's 'winbar' shows `needle` inside a segment
-- drawn with `group` ("%#Group#text").
local function winbar_has(needle, group)
  local pane = workspace and workspace.panes and workspace.panes.code
  if not pane or not vim.api.nvim_win_is_valid(pane.window) then
    return false
  end
  local bar = vim.wo[pane.window].winbar or ""
  for segment_group, text in bar:gmatch("%%#([%w_]+)#([^%%]*)") do
    if segment_group == group and text:find(needle, 1, true) then
      return true
    end
  end
  return false
end

local function has_group(pane_name, needle, group)
  if pane_name == "winbar" then
    return winbar_has(needle, group)
  end
  local pane = workspace and workspace.panes and workspace.panes[pane_name]
  if not pane then
    return false
  end
  local buffers = { { buffer = pane.buffer, namespace = namespace } }
  if pane_name == "details" then
    for _, card in pairs(state and state.comment_card_windows and state.comment_card_windows.cards or {}) do
      table.insert(buffers, { buffer = card.buffer, namespace = card_namespace })
    end
  end
  for _, target in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(target.buffer) then
      local marks = vim.api.nvim_buf_get_extmarks(target.buffer, target.namespace, 0, -1, { details = true })
      for row, line in ipairs(vim.api.nvim_buf_get_lines(target.buffer, 0, -1, false)) do
        local column = line:find(needle, 1, true)
        if column then
          column = column - 1
          for _, mark in ipairs(marks) do
            if covers(mark, row - 1, column) and mark[4].hl_group == group then
              return true
            end
          end
        end
      end
    end
  end
  for _, spec in pairs(state and state.comment_card_windows and state.comment_card_windows.specs or {}) do
    for row, line in ipairs(spec.lines or {}) do
      local column = line:find(needle, 1, true)
      if column then
        column = column - 1
        for _, mark in ipairs(spec.highlights or {}) do
          if mark.line == row - 1 and mark.start_col <= column and mark.end_col > column and mark.group == group then
            return true
          end
        end
      end
    end
  end
  return false
end

local checks = expectations[scene]
if not workspace or not checks then
  vim.api.nvim_echo({ { "COLORS_FAIL=" .. scene .. ":scene-not-ready" } }, false, {})
  return
end

if scene ~= "help" then
  local forbidden = {
    "<CR>",
    "<Esc>",
    "<C-d>",
    "<C-s>",
    "<C-r>",
    "<C-g>",
    "<C-w>",
    "<C-f>",
    "<Tab>",
    "]f",
    "[f",
    "]t",
    "[t",
  }
  for pane_name, pane in pairs(workspace.panes or {}) do
    local text = table.concat(vim.api.nvim_buf_get_lines(pane.buffer, 0, -1, false), "\n")
    for _, value in ipairs(forbidden) do
      if text:find(value, 1, true) then
        vim.api.nvim_echo({
          { ("COLORS_FAIL=%s:%s:key-legend:%s"):format(scene, pane_name, value) },
        }, false, {})
        return
      end
    end
  end
end

for _, check in ipairs(checks) do
  if not has_group(check.pane, check.needle, check.group) then
    vim.api.nvim_echo({
      { ("COLORS_FAIL=%s:%s:%s:%s"):format(scene, check.pane, check.needle, check.group) },
    }, false, {})
    return
  end
end

vim.api.nvim_echo({ { "COLORS_OK=" .. scene } }, false, {})
