-- Composer: a markdown editor in a float, for writing a reply or a
-- comment. Used by the thread window (replies to a review thread) and the
-- overview's conversation (comments and replies).
--
-- It opens focused, in Insert mode, with the draft restored. It grows with
-- its text between min and max height, maps the host's keys in Normal and
-- Insert mode, and completes @mentions. The host places it (`config`) and
-- decides what its keys do.
local keymap = require("proud.keymap")
local ui_window = require("proud.ui.window")

local M = {}

M.min_height = 3
M.max_height = 10
local sequence = 0

function M.trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Screen rows `text` (a string or lines) needs at `width` with wrapping,
-- between min and max height.
function M.rows(text, width, min_height, max_height)
  local lines = type(text) == "table" and text or vim.split(tostring(text or ""), "\n", { plain = true })
  width = math.max(1, width or 80)
  local rows = 0
  for _, line in ipairs(lines) do
    rows = rows + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
  end
  return math.max(min_height or M.min_height, math.min(max_height or M.max_height, rows))
end

local function height_for(buffer, width, min_height, max_height)
  return M.rows(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), width, min_height, max_height)
end

-- options:
--   config     nvim_open_win config: placement, plus title/footer if any
--   width      editor width
--   text       draft to restore
--   keys       { [keymap action] = function(composer) }, Normal and Insert
--   mentions   function() -> logins offered after "@"
--   highlight  winhighlight groups
--   min_height / max_height
--   on_grow(height)  the text needs a different height; re-place it
--   on_closed()      the window was closed some other way (:q)
-- Returns { buffer, window, height, text(), set_config(config), close() }.
function M.open(options)
  sequence = sequence + 1
  local min_height = options.min_height or M.min_height
  local max_height = options.max_height or M.max_height
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].filetype = "markdown"
  if options.text and options.text ~= "" then
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(options.text, "\n", { plain = true }))
  end
  local composer = { buffer = buffer, closed = false }
  composer.height = height_for(buffer, options.width, min_height, max_height)
  composer.window = vim.api.nvim_open_win(buffer, true, vim.tbl_extend("force", {
    style = "minimal",
    border = "rounded",
    zindex = 61,
  }, options.config or {}, {
    width = options.width,
    height = composer.height,
  }))
  ui_window.winhighlight(composer.window, options.highlight or {
    NormalFloat = "ProudBackground",
    FloatBorder = "ProudCardBorder",
    FloatTitle = "ProudMuted",
    FloatFooter = "ProudMuted",
  })
  vim.wo[composer.window].wrap = true
  vim.wo[composer.window].linebreak = true

  -- After the window closes the buffer is wiped; the text is kept.
  function composer.text()
    if vim.api.nvim_buf_is_valid(buffer) then
      composer.last_text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
    end
    return composer.last_text or ""
  end

  function composer.set_config(config)
    if vim.api.nvim_win_is_valid(composer.window) then
      vim.api.nvim_win_set_config(composer.window, vim.tbl_extend("force", config, {
        width = options.width,
        height = composer.height,
      }))
    end
  end

  local group = vim.api.nvim_create_augroup("ProudComposer" .. sequence, { clear = true })
  function composer.close()
    if composer.closed then
      return
    end
    composer.text()
    composer.closed = true
    pcall(vim.api.nvim_del_augroup_by_id, group)
    if vim.api.nvim_get_current_win() == composer.window then
      vim.cmd("stopinsert")
    end
    if vim.api.nvim_win_is_valid(composer.window) then
      pcall(vim.api.nvim_win_close, composer.window, true)
    end
  end

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = buffer,
    callback = function()
      local height = height_for(buffer, options.width, min_height, max_height)
      if height ~= composer.height then
        composer.height = height
        if options.on_grow then
          options.on_grow(height)
        else
          composer.set_config(vim.api.nvim_win_get_config(composer.window))
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(composer.window),
    callback = function()
      composer.text()
      vim.schedule(function()
        if not composer.closed then
          composer.closed = true
          pcall(vim.api.nvim_del_augroup_by_id, group)
          if options.on_closed then
            options.on_closed()
          end
        end
      end)
    end,
  })

  for action, callback in pairs(options.keys or {}) do
    keymap.map(buffer, { "n", "i" }, action, function()
      callback(composer)
    end)
  end
  if options.mentions then
    vim.keymap.set("i", "@", function()
      vim.schedule(function()
        if not composer.closed and vim.api.nvim_get_current_buf() == buffer and vim.fn.mode() == "i" then
          local names = options.mentions()
          if #names > 0 then
            vim.fn.complete(vim.fn.col("."), names)
          end
        end
      end)
      return "@"
    end, { buffer = buffer, expr = true, desc = "Mention a participant" })
  end

  local last = vim.api.nvim_buf_line_count(buffer)
  vim.api.nvim_win_set_cursor(composer.window, { last, #(vim.api.nvim_buf_get_lines(buffer, last - 1, last, false)[1] or "") })
  vim.cmd("startinsert!")
  return composer
end

return M
