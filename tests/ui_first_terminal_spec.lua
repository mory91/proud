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
  -- Never check out branches in the repository running the tests.
  background_checkout = false,
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

-- The compare page checks out branches: run it on a fixture repository,
-- never in the repository running the tests.
local fixture_repo = require("proud.fixture_repo")
local compare_repo = fixture_repo.create()
session.configure({ cwd = compare_repo.work })
session.open_compare("main", compare_repo.head_ref)
local compare_state = session.current and session.current.state
local compare_open = session.current ~= nil
  and session.current.feature == "branch_compare"
  and compare_state.loading == true
local compare_hydrated = vim.wait(15000, function()
  return compare_state.loading == false and compare_state.ahead == 2 and compare_state.diff.status == "ready"
end, 10)
compare_state.close()
fixture_repo.remove(compare_repo)
vim.api.nvim_echo({ { "UI_FIRST_COMPARE=" .. tostring(compare_open and compare_hydrated) } }, false, {})
credentials.reset()
