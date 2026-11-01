local M = {}

local definitions = {
  help = { group = "Global", description = "Toggle this help", keys = { "?" } },
  quit = { group = "Global", description = "Close the current scene", keys = { "q" } },

  next_item = { group = "Pull request list", description = "Select the next pull request", keys = { "j" } },
  previous_item = { group = "Pull request list", description = "Select the previous pull request", keys = { "k" } },
  next_tab = { group = "Pull request list", description = "Select the next source", keys = { "<Tab>" } },
  previous_tab = { group = "Pull request list", description = "Select the previous source", keys = { "<S-Tab>" } },
  open = { group = "Pull request list", description = "Open the selected pull request", keys = { "<CR>" } },
  edit_filter = { group = "Pull request list", description = "Edit pull request filters", keys = { "/" } },
  toggle_node = { group = "Overview", description = "Expand or collapse the selected sidebar node", keys = { "<Space>" } },
  next_node = { group = "Overview", description = "Select the next sidebar node", keys = { "j" } },
  previous_node = { group = "Overview", description = "Select the previous sidebar node", keys = { "k" } },
  expand_node = { group = "Overview", description = "Expand the selected sidebar branch", keys = { "l", "o" } },
  collapse_node = { group = "Overview", description = "Collapse the selected sidebar branch", keys = { "h", "c" } },
  scroll_preview_down = { group = "Pull request list", description = "Scroll the pull request description down", keys = { "<C-d>" } },
  scroll_preview_up = { group = "Pull request list", description = "Scroll the pull request description up", keys = { "<C-u>" } },
  focus_preview = { group = "Pull request list", description = "Focus the pull request preview", keys = { "<C-p>" } },
  return_to_list = { group = "Pull request list", description = "Return to the pull request list", keys = { "<C-l>" } },

  toggle_viewed = { group = "Overview", description = "Toggle the selected file viewed", keys = { "v" } },
  open_diff = { group = "Overview", description = "Open the complete file diff", keys = { "<CR>", "d" } },
  comment = { group = "Overview", description = "Draft a pull request comment", keys = { "c" } },
  open_review = { group = "Overview", description = "Compose a pull request review", keys = { "R" } },

  next_file = { group = "Single-file review", description = "Select the next file", keys = { "]f" } },
  previous_file = { group = "Single-file review", description = "Select the previous file", keys = { "[f" } },
  select_file = { group = "Single-file review", description = "Select the focused file", keys = { "<CR>" } },
  next_thread = { group = "Single-file review", description = "Select the next review thread", keys = { "]t" } },
  previous_thread = { group = "Single-file review", description = "Select the previous review thread", keys = { "[t" } },
  reply = { group = "Single-file review", description = "Reply to the selected thread", keys = { "r" } },
  resolve = { group = "Single-file review", description = "Resolve the selected thread", keys = { "R" } },

  swap_branches = { group = "Compare", description = "Swap base and head branches", keys = { "S" } },
  toggle_compare_mode = { group = "Compare", description = "Toggle two-dot and three-dot compare", keys = { "<C-d>" } },
  open_pull_request = { group = "Compare", description = "Open the pull request for this compare", keys = { "P" } },

  submit_token = { group = "Authentication", description = "Submit the focused token", keys = { "<CR>" } },
  cancel_token = { group = "Authentication", description = "Cancel token entry", keys = { "<Esc>" } },

  next_review_decision = { group = "Review", description = "Select the next review decision", keys = { "<Tab>" } },
  previous_review_decision = { group = "Review", description = "Select the previous review decision", keys = { "<S-Tab>" } },
  focus_review_decisions = { group = "Review", description = "Focus the review decision controls", keys = { "<C-g>" } },
  focus_review_body = { group = "Review", description = "Focus the review body editor", keys = { "<C-b>" } },
  submit_review = { group = "Review", description = "Submit the composed pull request review", keys = { "S" } },
}

local groups = {
  "Global",
  "Pull request list",
  "Overview",
  "Single-file review",
  "Compare",
  "Review",
  "Authentication",
}

local config = {}

local function normalize_keys(value)
  if value == false or value == "" then
    return {}
  end
  if type(value) == "string" then
    return { value }
  end
  if type(value) ~= "table" then
    return {}
  end
  local keys = {}
  for _, key in ipairs(value) do
    if type(key) == "string" and key ~= "" then
      table.insert(keys, key)
    end
  end
  return keys
end

function M.defaults()
  local values = {}
  for action, definition in pairs(definitions) do
    values[action] = vim.deepcopy(definition.keys)
  end
  return values
end

function M.setup(overrides)
  overrides = overrides or {}
  for action in pairs(overrides) do
    if not definitions[action] then
      error("Unknown Proud keymap action: " .. tostring(action))
    end
  end
  config = M.defaults()
  for action, value in pairs(overrides) do
    config[action] = normalize_keys(value)
  end
  return config
end

function M.keys(action)
  return vim.deepcopy(config[action] or {})
end

function M.label(action)
  return table.concat(M.keys(action), " / ")
end

function M.help_groups()
  local result = {}
  for _, title in ipairs(groups) do
    local items = {}
    for action, definition in pairs(definitions) do
      if definition.group == title then
        table.insert(items, {
          action = action,
          lhs = M.label(action),
          description = definition.description,
        })
      end
    end
    table.sort(items, function(left, right)
      return left.action < right.action
    end)
    table.insert(result, { title = title, items = items })
  end
  return result
end

function M.map(buffer, mode, action, callback, description)
  for _, lhs in ipairs(M.keys(action)) do
    vim.keymap.set(mode, lhs, callback, {
      buffer = buffer,
      silent = false,
      nowait = true,
      desc = description or (definitions[action] and definitions[action].description or action),
    })
  end
end

-- Removes an action's buffer-local mappings (used on real file buffers
-- when a scene stops using them).
function M.unmap(buffer, mode, action)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  for _, lhs in ipairs(M.keys(action)) do
    pcall(vim.keymap.del, mode, lhs, { buffer = buffer })
  end
end

local function has_action_map(buffer, mode, action)
  for _, lhs in ipairs(M.keys(action)) do
    local raw_lhs = vim.api.nvim_replace_termcodes(lhs, true, false, true)
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buffer, mode)) do
      if mapping.lhsraw == raw_lhs or mapping.lhs == lhs then
        return true
      end
    end
  end
  return false
end

function M.map_workspace(workspace, mode, action, callback, description)
  for _, pane in pairs(workspace.panes or {}) do
    if pane.buffer
      and vim.api.nvim_buf_is_valid(pane.buffer)
      and not has_action_map(pane.buffer, mode, action)
    then
      M.map(pane.buffer, mode, action, callback, description)
    end
  end
end

function M.open_help()
  require("proud.session").open_help()
end

function M.bind_common_workspace(workspace, options)
  options = options or {}
  local close = options.on_quit or function()
    require("proud.ui").close_workspace(workspace)
  end
  M.map_workspace(workspace, "n", "help", options.on_help or M.open_help, "Open help")
  M.map_workspace(workspace, "n", "quit", close, "Close current scene")
end

function M.bind_common_buffer(buffer, options)
  options = options or {}
  local close = options.on_quit or function() end
  M.map(buffer, "n", "help", options.on_help or M.open_help, "Open help")
  M.map(buffer, "n", "quit", close, "Close current scene")
end

M.setup()

return M
