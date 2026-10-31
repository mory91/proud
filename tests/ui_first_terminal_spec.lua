local session = require("proud.session")
local credentials = require("proud.loader").load("github_credentials")
local provider = require("proud.provider")

local pull = provider.normalize_pull_request({
  number = 905,
  title = "Terminal hydration",
  body = "Visible after async hydration",
  commits = { { sha = "abc1234", message = "Terminal subject\n\nTerminal body" } },
  files = { { filename = "src/terminal.ts", status = "MODIFIED", additions = 1, deletions = 0 } },
})

local callback
local fake_client = {
  get_repository = function(_, done)
    vim.defer_fn(function()
      done(true, { full_name = "acme/widget" })
    end, 700)
  end,
  get_pull_request = function(_, _, done)
    callback = done
    vim.defer_fn(function()
      done(true, vim.deepcopy(pull))
    end, 500)
  end,
}

session.configure({
  kind = "github",
  repository = "acme/widget",
  token = "github_pat_terminal_ui_first",
  token_path = vim.fn.tempname(),
  credential = false,
  client = fake_client,
  cwd = vim.fn.getcwd(),
})

session.open_overview(905)
local opened = vim.wait(2000, function()
  return session.current
    and session.current.feature == "pull_request_overview"
    and session.current.state.pull.number == 905
end, 10)
local details = session.current and session.current.state.workspace.panes.details.buffer
local loading_visible = details ~= nil
  and table.concat(vim.api.nvim_buf_get_lines(details, 0, -1, false), "\n"):find("Loading pull request details...", 1, true) ~= nil
local tree = require("proud.components.tree")
local overview_state = session.current and session.current.state
if overview_state then
  vim.api.nvim_feedkeys("jj", "x", false)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Space>", true, false, true), "x", false)
  overview_state.refresh()
end
vim.api.nvim_echo({ { "UI_FIRST_OPEN=" .. tostring(opened and loading_visible) } }, false, {})

local hydrated = vim.wait(3000, function()
  return session.current
    and session.current.state.pull.title == "Terminal hydration"
end, 10)
local sidebar = session.current and session.current.state.workspace.panes.sidebar.buffer
local layout_preserved = overview_state
  and tree.selected(overview_state.sidebar).id == "commits"
  and tree.find(overview_state.sidebar, "commits").expanded == false
if layout_preserved then
  vim.api.nvim_feedkeys("l", "x", false)
end
local opened_after_hydration = overview_state
  and tree.find(overview_state.sidebar, "commits").expanded == true
if opened_after_hydration then
  vim.api.nvim_feedkeys("h", "x", false)
  vim.api.nvim_feedkeys("l", "x", false)
  tree.select(overview_state.sidebar, "files")
  overview_state.refresh()
  vim.api.nvim_feedkeys("jjjj", "x", false)
end
local selected_row
if overview_state then
  _, selected_row = tree.row(overview_state.sidebar)
end
local keyboard_navigation = selected_row ~= nil and selected_row > 3
local safe_commit = sidebar ~= nil
  and table.concat(vim.api.nvim_buf_get_lines(sidebar, 0, -1, false), "\n"):find("abc1234 Terminal subject", 1, true) ~= nil
vim.api.nvim_echo({ { "UI_FIRST_HYDRATED=" .. tostring(
  hydrated and layout_preserved and opened_after_hydration and keyboard_navigation and safe_commit
) } }, false, {})

local compare_callback
local provider_module = require("proud.provider")
provider_module.git = function()
  return {
    compare = function(_, _, _, callback)
      compare_callback = callback
    end,
  }
end
session.open_compare("main", "feature")
local compare_open = vim.wait(2000, function()
  return session.current and session.current.feature == "branch_compare"
end, 10)
vim.api.nvim_feedkeys("S", "x", false)
compare_callback(true, {
  "3\t12\n",
  "abc1234 Feature commit\n",
  "1\t0\tsrc/feature.ts\n",
})
local compare_hydrated = vim.wait(2000, function()
  local state = session.current and session.current.state
  return state and state.loading == false and state.ahead == 3 and state.behind == 12
end, 10)
vim.api.nvim_echo({ { "UI_FIRST_COMPARE=" .. tostring(compare_open and compare_hydrated) } }, false, {})
credentials.reset()
