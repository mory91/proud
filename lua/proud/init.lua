local util = require("proud.util")
local session = require("proud.session")
local keymap = require("proud.keymap")

local M = {
  config = {
    provider = {
      kind = "github",
      cache_items = 128,
      query_debounce_ms = 250,
      description_debounce_ms = 80,
    },
    keymaps = keymap.defaults(),
    benchmarks = {
      enforce_sla = true,
    },
    ui = {
      -- Proud's themed tabline; false keeps your own 'tabline'.
      tabline = true,
      -- Turn on 'termguicolors' when applying themes; false leaves it alone.
      termguicolors = true,
      theme = "proud-sunset",
      themes = {},
      windows = {
        margin = { top = 3, bottom = 2, left = 2, right = 2 },
        gap = 3,
      },
    },
  },
}

local commands = {
  prs = function(options)
    session.open_pull_requests(options)
  end,
  open = function(options)
    session.open_overview(tonumber(options.args))
  end,
  diff = function(options)
    local number = tonumber(options.args:match("(%d+)"))
    if not number then
      vim.notify("Usage: Proud diff {number}", vim.log.levels.WARN)
      return
    end
    session.open_diff(number)
  end,
  compare = function(options)
    local base, head = options.args:match("^(%S+)%s+(%S+)$")
    if not base then
      vim.notify("Usage: Proud compare {base} {head}", vim.log.levels.WARN)
      return
    end
    session.open_compare(base, head)
  end,
  help = function()
    session.open_help()
  end,
  demo = function(options)
    session.demo(options.args ~= "" and options.args or nil)
  end,
}

function M.setup(options)
  options = options or {}
  local general = vim.deepcopy(options)
  local keymap_overrides = general.keymaps
  general.keymaps = nil
  M.config = util.deep_merge(M.config, general)
  M.config.keymaps = keymap.setup(keymap_overrides)
  require("proud.ui.theme").set_manage_termguicolors(M.config.ui.termguicolors)
  require("proud.theme").setup(M.config.ui)
  if M.config.ui.tabline then
    require("proud.ui.tabline").enable()
  else
    require("proud.ui.tabline").disable()
  end
  require("proud.ui").configure(M.config.ui)
  require("proud.ui").set_status_segments({
    { " GitHub ", "ProudMuted" },
    { " api ", "ProudSuccessText" },
    { "✓ ", "ProudSuccess" },
  })
  session.configure(M.config.provider)
  vim.api.nvim_create_user_command("Proud", function(command_options)
    local subcommand = vim.split(command_options.args, "%s+", { trimempty = true })[1]
    if not subcommand then
      vim.notify("Usage: Proud {prs|open|diff|compare|help|demo}", vim.log.levels.INFO)
      return
    end
    local handler = commands[subcommand]
    if not handler then
      vim.notify("Unknown Proud command: " .. subcommand, vim.log.levels.ERROR)
      return
    end
    handler({
      args = command_options.args:gsub("^%S+%s*", ""),
      fargs = vim.list_slice(vim.split(command_options.args, "%s+", { trimempty = true }), 2),
      bang = command_options.bang,
    })
  end, {
    nargs = "*",
    complete = function()
      return vim.tbl_keys(commands)
    end,
    desc = "Proud pull request reviewer",
  })
end

function M.command(name, callback)
  commands[name] = callback
end

function M.load_feature(name)
  return require("proud.loader").load(name)
end

return M
