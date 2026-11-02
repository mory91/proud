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
  -- The pull request's diff: the compare page with the PR's threads.
  diff = {
    { pane = "winbar", needle = "main", group = "ProudAccentText" },
    { pane = "winbar", needle = "feat/task-retry-backoff", group = "ProudSuccessText" },
    { pane = "winbar", needle = "packages/runner/src/config.ts", group = "ProudMuted" },
    { pane = "winbar", needle = "[+", group = "ProudAccentText" },
    { pane = "line", needle = "maxDelayMs: number", group = "ProudAddLine" },
    { pane = "sign", needle = "◆", group = "ProudWarning" },
    { pane = "sidebar", needle = "Compare", group = "ProudBright" },
    { pane = "sidebar", needle = "three-dot, from merge base", group = "ProudMuted" },
    { pane = "sidebar", needle = "#482", group = "ProudMuted" },
    { pane = "sidebar", needle = "All changes", group = "ProudBright" },
    { pane = "sidebar", needle = "Add exponential backoff", group = "ProudMuted" },
    { pane = "sidebar", needle = "+5", group = "ProudSuccessText" },
    { pane = "sidebar", needle = "◆1", group = "ProudWarning" },
  },
  compare = {
    { pane = "sidebar", needle = "Compare", group = "ProudBright" },
    { pane = "sidebar", needle = "ahead", group = "ProudSuccessText" },
    { pane = "sidebar", needle = "behind", group = "ProudWarning" },
    { pane = "sidebar", needle = "no PR yet", group = "ProudMuted" },
    { pane = "sidebar", needle = "feat/task-retry-backoff", group = "ProudSuccessText" },
    { pane = "sidebar", needle = "Commits", group = "ProudBright" },
    { pane = "sidebar", needle = "packages/runner/src/config.ts", group = "ProudBright" },
    { pane = "sidebar", needle = "+5", group = "ProudSuccessText" },
    { pane = "sidebar", needle = "−0", group = "ProudDangerText" },
    { pane = "winbar", needle = "...", group = "ProudMuted" },
    { pane = "line", needle = "maxDelayMs: number", group = "ProudAddLine" },
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
if state and state.diff and state.diff.scene then
  -- The compare page: wait for the checkout, then check the sidebar and
  -- the real file shown in the diff pane ("code").
  local diff = state.diff
  vim.wait(15000, function()
    return diff.status ~= "loading" and (diff.status ~= "ready" or next(diff.scene.handles) ~= nil)
  end, 20)
  workspace = {
    panes = {
      sidebar = state.workspace.panes.sidebar,
      code = { buffer = vim.api.nvim_win_get_buf(diff.scene.window), window = diff.scene.window },
    },
  }
end
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

-- Editable diff: a whole-line highlight (inline diff) on the line with
-- `needle`, or a thread sign `needle` drawn with `group`.
local function line_has(needle, group)
  local pane = workspace and workspace.panes and workspace.panes.code
  local inline = vim.api.nvim_get_namespaces().proud_inline_diff
  if not pane or not inline then
    return false
  end
  for row, line in ipairs(vim.api.nvim_buf_get_lines(pane.buffer, 0, -1, false)) do
    if line:find(needle, 1, true) then
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(pane.buffer, inline, { row - 1, 0 }, { row - 1, -1 }, { details = true })) do
        if mark[4].line_hl_group == group then
          return true
        end
      end
    end
  end
  return false
end

local function sign_has(needle, group)
  local pane = workspace and workspace.panes and workspace.panes.code
  local threads = vim.api.nvim_get_namespaces().proud_diff_threads
  if not pane or not threads then
    return false
  end
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(pane.buffer, threads, 0, -1, { details = true })) do
    if vim.trim(mark[4].sign_text or "") == needle and mark[4].sign_hl_group == group then
      return true
    end
  end
  return false
end

local function has_group(pane_name, needle, group)
  if pane_name == "winbar" then
    return winbar_has(needle, group)
  elseif pane_name == "line" then
    return line_has(needle, group)
  elseif pane_name == "sign" then
    return sign_has(needle, group)
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
