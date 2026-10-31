local ui = require("proud.ui")
local keymap = require("proud.keymap")

local M = {}

local decisions = {
  {
    event = "COMMENT",
    label = "Comment",
    description = "Submit feedback without a merge decision",
  },
  {
    event = "APPROVE",
    label = "Approve",
    description = "Approve the pull request for merging",
  },
  {
    event = "REQUEST_CHANGES",
    label = "Request changes",
    description = "Block merging until the review is addressed",
  },
}

local function body_lines(value)
  if type(value) == "table" then
    return vim.deepcopy(value)
  end
  if type(value) == "string" and value ~= "" then
    return vim.split(value, "\n", { plain = true })
  end
  return { "" }
end

function M.create(pull, options)
  options = options or {}
  local selected = 1
  for index, decision in ipairs(decisions) do
    if decision.event == tostring(options.event or ""):upper():gsub("[%s%-]", "_") then
      selected = index
    end
  end
  return {
    pull = vim.deepcopy(pull or {}),
    decisions = vim.deepcopy(decisions),
    selected = selected,
    body_lines = body_lines(options.body),
    status = "",
    status_group = "ProudMuted",
    submitting = false,
  }
end

function M.selected(state)
  return state.decisions[state.selected]
end

function M.select_delta(state, delta)
  local count = #state.decisions
  state.selected = (state.selected - 1 + (tonumber(delta) or 0)) % count + 1
  return M.selected(state)
end

function M.set_body(state, value)
  state.body_lines = body_lines(value)
  return table.concat(state.body_lines, "\n")
end

function M.validate(state, body)
  local decision = M.selected(state)
  body = body or table.concat(state.body_lines, "\n")
  if not decision then
    return false, "Select a review decision"
  end
  if decision.event ~= "APPROVE" and vim.trim(body) == "" then
    return false, "Write a review body before submitting"
  end
  return true, body
end

function M.render(state, width)
  width = math.max(24, math.floor(tonumber(width) or 44))
  local lines = {
    ("Review #%s"):format(tostring(state.pull.number or "")),
    string.rep("─", width),
  }
  local highlights = {}
  local labels = vim.tbl_map(function(decision)
    return decision.label
  end, state.decisions)
  local buttons = ui.button_layout(labels, state.selected, width, {
    selected_padding = 2,
    item_padding = 1,
    separator_width = 1,
  })
  table.insert(lines, buttons.text)
  for _, item in ipairs(buttons.highlights) do
    table.insert(highlights, {
      line = #lines - 1,
      start_col = item[2],
      end_col = item[3],
      group = item[4],
    })
  end
  table.insert(lines, string.rep("─", width))
  local selected = M.selected(state)
  table.insert(lines, selected.description)
  table.insert(lines, "")
  table.insert(lines, state.status ~= "" and state.status or "Review body is ready on the right")
  table.insert(lines, "")
  table.insert(lines, state.submitting and "Submitting review..." or "Submit review")
  ui.view.span(lines, highlights, 0, "Review", "ProudBright")
  ui.view.span(lines, highlights, 0, tostring(state.pull.number or ""), "ProudAccentText")
  ui.view.span(lines, highlights, 4, selected.description, "ProudMuted")
  ui.view.span(
    lines,
    highlights,
    6,
    state.status ~= "" and state.status or "Review body is ready on the right",
    state.status == "" and "ProudMuted" or (state.status_group or "ProudSuccessText")
  )
  ui.view.span(lines, highlights, 8, "Submit review", state.submitting and "ProudMuted" or "ProudAccentText")
  return {
    lines = lines,
    highlights = highlights,
    highlight_format = "table",
  }
end

function M.render_body(state)
  local highlights = {}
  for row, line in ipairs(state.body_lines) do
    if line ~= "" then
      table.insert(highlights, {
        line = row - 1,
        start_col = 0,
        end_col = #line,
        group = "ProudBright",
      })
    end
  end
  return {
    lines = vim.deepcopy(state.body_lines),
    highlights = highlights,
  }
end

function M.render_panes(state, options)
  options = options or {}
  return {
    decisions = M.render(state, options.decisions_width or 42),
    body = M.render_body(state),
  }
end

function M.submit(state, options, callback)
  options = options or {}
  callback = callback or function() end
  if state.submitting then
    return false, "A review is already being submitted"
  end
  local valid, body_or_error = M.validate(state)
  if not valid then
    state.status = body_or_error
    state.status_group = "ProudDangerText"
    if state.refresh then
      state.refresh()
    end
    callback(false, { message = body_or_error })
    return false, body_or_error
  end
  local decision = M.selected(state)
  state.submitting = true
  state.status = ""
  state.status_group = "ProudMuted"
  if state.refresh then
    state.refresh()
  end
  local function finish(ok, result)
    state.submitting = false
    state.status = ok and "Review submitted" or (result and result.message or "Review submission failed")
    state.status_group = ok and "ProudSuccessText" or "ProudDangerText"
    if state.refresh then
      state.refresh()
    end
    if ok and options.on_success then
      options.on_success(result)
    end
    callback(ok, result)
  end
  if options.on_submit then
    options.on_submit(decision.event, body_or_error, finish)
  else
    vim.schedule(function()
      finish(true, { event = decision.event })
    end)
  end
  return true
end

function M.attach(buffer, state, options)
  options = options or {}
  local workspace = assert(options.workspace, "review workspace is required")
  local decision_buffer = ui.workspace_buffer(workspace, "decisions")
  local body_buffer = ui.workspace_buffer(workspace, "body")
  local decision_window = ui.workspace_window(workspace, "decisions")
  local body_window = ui.workspace_window(workspace, "body")

  local function sync_body()
    if vim.api.nvim_buf_is_valid(body_buffer) then
      state.body_lines = vim.api.nvim_buf_get_lines(body_buffer, 0, -1, false)
    end
  end

  local function refresh()
    sync_body()
    local width = vim.api.nvim_win_is_valid(decision_window)
      and vim.api.nvim_win_get_width(decision_window)
      or 42
    ui.render(decision_buffer, M.render(state, width))
  end
  state.refresh = refresh

  keymap.map_workspace(workspace, "n", "next_review_decision", function()
    M.select_delta(state, 1)
    refresh()
  end, "Select the next review decision")
  keymap.map_workspace(workspace, "n", "previous_review_decision", function()
    M.select_delta(state, -1)
    refresh()
  end, "Select the previous review decision")
  keymap.map_workspace(workspace, "n", "focus_review_decisions", function()
    ui.focus_workspace_pane(workspace, "decisions")
  end, "Focus review decisions")
  keymap.map_workspace(workspace, "n", "focus_review_body", function()
    ui.focus_workspace_pane(workspace, "body")
  end, "Focus review body")
  keymap.map_workspace(workspace, "n", "submit_review", function()
    sync_body()
    M.submit(state, options)
  end, "Submit pull request review")
  keymap.bind_common_workspace(workspace, {
    on_quit = options.on_quit or function()
      ui.close_workspace(workspace)
    end,
  })
  if vim.api.nvim_buf_is_valid(body_buffer) then
    vim.bo[body_buffer].modifiable = true
    vim.bo[body_buffer].readonly = false
  end
  refresh()
end

function M.open(state, options)
  options = options or {}
  local name = "proud://pr/" .. tostring(state.pull.number or "") .. "/review"
  local panes = M.render_panes(state)
  local workspace = ui.open_workspace(name, {
    {
      name = "decisions",
      buffer_name = name .. "/decisions",
      title = "#" .. tostring(state.pull.number or "") .. " review",
      view = panes.decisions,
      weight = 0.34,
    },
    {
      name = "body",
      buffer_name = name .. "/body",
      title = "#" .. tostring(state.pull.number or "") .. " review",
      view = panes.body,
      weight = 0.66,
    },
  }, {
    focus = "body",
    title = "#" .. tostring(state.pull.number or "") .. " review",
    statusline = "#" .. tostring(state.pull.number or "") .. " review",
    on_resize = function()
      if state.refresh then
        state.refresh()
      end
    end,
  })
  state.workspace = workspace
  local buffer = ui.workspace_buffer(workspace, "body")
  M.attach(buffer, state, vim.tbl_extend("force", options, { workspace = workspace }))
  ui.focus_workspace_pane(workspace, "body")
  return buffer, workspace
end

return M
