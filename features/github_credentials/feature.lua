local github = require("proud.github")
local ui = require("proud.ui")
local util = require("proud.util")

local M = {
  name = "github_credentials",
}

local session_token = nil
local uv = vim.uv or vim.loop
local separator = string.rep("─", 58)
local prompt_sign_namespace = vim.api.nvim_create_namespace("proud_credentials_prompt_sign")
local prompt_sign_mark_id = 1

local function schedule(callback, ...)
  local values = { ... }
  vim.schedule(function()
    callback(unpack(values))
  end)
end

function M.default_token_path(options)
  options = options or {}
  return options.token_path
    or options.token_file
    or vim.env.PROUD_GITHUB_TOKEN_FILE
    or (vim.fn.stdpath("state") .. "/proud/github-token")
end

function M.normalize_token(value)
  local token = util.trim(tostring(value or ""))
  token = token:gsub("^[Bb]earer%s+", "")
  token = token:gsub("^[Tt]oken%s+", "")
  return util.trim(token)
end

function M.read_token(path)
  path = M.default_token_path({ token_path = path })
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local value = file:read("*a")
  file:close()
  return M.normalize_token(value)
end

function M.write_token(path, token)
  path = M.default_token_path({ token_path = path })
  token = M.normalize_token(token)
  if token == "" then
    return false, "Credential token is empty"
  end
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local temporary = path .. ".tmp"
  local file, open_error = io.open(temporary, "w")
  if not file then
    return false, "Could not create credential file: " .. tostring(open_error)
  end
  file:write(token .. "\n")
  file:close()
  local chmod_ok, chmod_error = uv.fs_chmod(temporary, 384)
  if not chmod_ok then
    pcall(uv.fs_unlink, temporary)
    return false, "Could not secure credential file: " .. tostring(chmod_error)
  end
  local rename_ok, rename_error = uv.fs_rename(temporary, path)
  if not rename_ok then
    pcall(uv.fs_unlink, temporary)
    return false, "Could not save credential file: " .. tostring(rename_error)
  end
  return true
end

local function environment_token()
  return M.normalize_token(vim.env.PROUD_GITHUB_TOKEN or vim.env.GITHUB_TOKEN)
end

function M.resolve_candidate(options, callback)
  options = options or {}
  local explicit = M.normalize_token(options.token)
  if explicit ~= "" then
    schedule(callback, explicit, "explicit")
    return
  end
  local environment = environment_token()
  if environment ~= "" then
    schedule(callback, environment, "environment")
    return
  end
  local stored = M.read_token(M.default_token_path(options))
  if stored and stored ~= "" then
    schedule(callback, stored, "stored")
    return
  end
  if options.credential == false then
    schedule(callback, nil, nil)
    return
  end
  github.resolve_token({
    base_url = options.base_url,
    git_host = options.git_host,
    cwd = options.cwd,
  }, function(token)
    callback(M.normalize_token(token), token and "git-credential" or nil)
  end)
end

local function sanitize_error(value)
  local message = type(value) == "table" and (value.message or value.error or "") or tostring(value or "")
  message = util.trim(message)
  message = message:gsub("[Bb]earer%s+%S+", "Bearer [redacted]")
  message = message:gsub("github_pat_[%w_]+", "[redacted]")
  return message ~= "" and message or "GitHub credential validation failed"
end

function M.create(options)
  options = options or {}
  local token_path = M.default_token_path(options)
  return {
    token_path = token_path,
    short_token_path = vim.fn.fnamemodify(token_path, ":~"),
    error = options.error and sanitize_error(options.error) or nil,
    busy = options.busy or false,
    options = options,
    prompt_count = options.prompt_count or 0,
  }
end

local function add_span(lines, highlights, line, needle, group)
  local text = lines[line + 1] or ""
  local start_col = text:find(needle, 1, true)
  if start_col then
    table.insert(highlights, {
      line = line,
      start_col = start_col - 1,
      end_col = start_col - 1 + #needle,
      group = group,
    })
  end
end

function M.render(state)
  local lines = {
    "proud credentials",
    separator,
    "GitHub token required",
    state.error and ("Error  " .. state.error) or "",
    state.busy and "Validating GitHub repository access…" or "No reusable credential is available.",
    state.busy and "This page will close when validation succeeds." or "type the token in the page below with repository read access.",
    "",
    "The token is hidden while entered and stored owner-only.",
    "It is reused on later launches and in later scenes.",
    "Help is available from every scene.",
    "",
    "Credential  " .. (state.short_token_path or vim.fn.fnamemodify(state.token_path, ":~")),
    "",
    state.busy and "Validating…" or "Submit or cancel from the focused token field.",
  }
  local highlights = {}
  add_span(lines, highlights, 0, "proud credentials", "ProudAccentText")
  add_span(lines, highlights, 2, "GitHub token required", "ProudAccentText")
  add_span(lines, highlights, 3, "Error", "ProudDangerText")
  if not state.busy then
    add_span(lines, highlights, 5, "type the token in the page below", "ProudAccentText")
    add_span(lines, highlights, 5, "repository read access", "ProudSuccessText")
  end
  add_span(lines, highlights, 7, "hidden", "ProudSuccessText")
  add_span(lines, highlights, 7, "owner-only", "ProudSuccessText")
  add_span(lines, highlights, 8, "reused", "ProudSuccessText")
  add_span(lines, highlights, 9, "Help", "ProudAccentText")
  add_span(lines, highlights, 11, "Credential", "ProudMuted")
  add_span(lines, highlights, 13, state.busy and "Validating…" or "Submit", "ProudAccentText")
  return { lines = lines, highlights = highlights }
end

function M.submit(state, value, options, callback)
  options = vim.tbl_extend("force", state.options or {}, options or {})
  local token = M.normalize_token(value)
  if token == "" then
    state.error = "Credential token is empty"
    state.busy = false
    if state.refresh then
      state.refresh()
    end
    if callback then
      callback(false, state.error)
    end
    return
  end
  state.busy = true
  state.error = nil
  if state.refresh then
    state.refresh()
  end
  local validate = options.validate or function(candidate, done)
    local client = github.new({
      token = candidate,
      repository = options.repository,
      base_url = options.base_url,
      cwd = options.cwd,
    })
    client:get_repository(done)
  end
  validate(token, function(ok, result)
    if not ok then
      state.error = sanitize_error(result)
      state.busy = false
      if state.clear_prompt then
        state.clear_prompt()
      end
      if state.refresh then
        state.refresh()
      end
      if callback then
        callback(false, state.error)
      end
      return
    end
    local saved, save_error = M.write_token(state.token_path, token)
    if not saved then
      state.error = save_error
      state.busy = false
      if state.clear_prompt then
        state.clear_prompt()
      end
      if state.refresh then
        state.refresh()
      end
      if callback then
        callback(false, state.error)
      end
      return
    end
    session_token = token
    state.token = token
    state.busy = false
    state.error = nil
    if state.refresh then
      state.refresh()
    end
    if options.on_success then
      options.on_success(token)
    end
    if callback then
      callback(true, token)
    end
  end)
end

function M.mask_prompt(buffer, window)
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  if window and vim.api.nvim_win_is_valid(window) then
    vim.wo[window].conceallevel = 2
    vim.wo[window].concealcursor = "nvic"
    ui.winhighlight(window, {
      NormalFloat = "ProudBackground",
      FloatBorder = "ProudAccent",
      Conceal = "ProudAccentText",
    })
  end
  if not vim.b[buffer].proud_prompt_masked then
    vim.api.nvim_buf_call(buffer, function()
      vim.cmd("syntax clear")
      vim.cmd("syntax match ProudPromptToken /./ conceal cchar=*")
    end)
    vim.api.nvim_buf_set_extmark(buffer, prompt_sign_namespace, 0, 0, {
      id = prompt_sign_mark_id,
      sign_text = "❯",
      sign_hl_group = "ProudAccentText",
      right_gravity = false,
    })
    vim.b[buffer].proud_prompt_masked = true
  end
end

local function close_windows(state)
  if state.closed then
    return
  end
  state.closed = true
  if state.lifecycle then
    state.lifecycle.close()
    return
  end
  if state.prompt_header and vim.api.nvim_win_is_valid(state.prompt_header.window) then
    pcall(vim.api.nvim_win_close, state.prompt_header.window, true)
  end
  if state.prompt_window and vim.api.nvim_win_is_valid(state.prompt_window) then
    pcall(vim.api.nvim_win_close, state.prompt_window, true)
  end
  if state.prompt_buffer and vim.api.nvim_buf_is_valid(state.prompt_buffer) then
    pcall(vim.api.nvim_buf_delete, state.prompt_buffer, { force = true })
  end
  if state.window and vim.api.nvim_win_is_valid(state.window) then
    pcall(vim.api.nvim_win_close, state.window, true)
  end
  if state.header and vim.api.nvim_win_is_valid(state.header.window) then
    pcall(vim.api.nvim_win_close, state.header.window, true)
  end
  if state.prompt_header and vim.api.nvim_buf_is_valid(state.prompt_header.buffer) then
    pcall(vim.api.nvim_buf_delete, state.prompt_header.buffer, { force = true })
  end
  if state.header and vim.api.nvim_buf_is_valid(state.header.buffer) then
    pcall(vim.api.nvim_buf_delete, state.header.buffer, { force = true })
  end
  if state.buffer and vim.api.nvim_buf_is_valid(state.buffer) then
    pcall(vim.api.nvim_buf_delete, state.buffer, { force = true })
  end
  state.prompt_header = nil
  state.header = nil
  state.prompt_window = nil
  state.prompt_buffer = nil
  state.window = nil
end

local function request_close_windows(state)
  if state.lifecycle then
    state.lifecycle.request_close()
    return
  end
  vim.schedule(function()
    close_windows(state)
  end)
end

function M.open(state, options)
  state.options = vim.tbl_extend("force", state.options or {}, options or {})
  local view = M.render(state)
  local buffer, window, header = ui.open_float(view, "proud://credentials", {
    width = 68,
    height = #view.lines + 2,
    header = {
      buffer_name = "proud://headers/credentials",
      title = "proud credentials",
      text = "proud credentials",
      text_group = "ProudAccentText",
      normal_group = "ProudBackground",
    },
  })
  state.buffer = buffer
  state.window = window
  state.header = header
  local modal_config = vim.api.nvim_win_get_config(window)
  -- Unnamed and never reused; no undo history so the token is not retained.
  local prompt_buffer = ui.buffer(nil, {
    bo = { bufhidden = "wipe", modifiable = true, undofile = false, undolevels = -1 },
  })
  vim.api.nvim_buf_set_lines(prompt_buffer, 0, -1, false, { "" })
  local prompt_window = vim.api.nvim_open_win(prompt_buffer, true, {
    relative = "editor",
    row = modal_config.row + modal_config.height + 1,
    col = modal_config.col,
    width = modal_config.width,
    height = 1,
    style = "minimal",
    border = "rounded",
    focusable = true,
  })
  ui.winhighlight(prompt_window, { NormalFloat = "ProudBackground", FloatBorder = "ProudAccent" })
  ui.window_options(prompt_window, { signcolumn = "yes" })
  local prompt_header = ui.open_pane_header(prompt_window, {
    buffer_name = "proud://headers/token",
    title = "token",
    text = "Token",
    text_group = "ProudAccentText",
      normal_group = "ProudBackground",
  })
  state.prompt_buffer = prompt_buffer
  state.prompt_window = prompt_window
  state.prompt_header = prompt_header
  local lifecycle = ui.create_scene_lifecycle({
    on_close = function()
      state.prompt_header = nil
      state.header = nil
      state.prompt_window = nil
      state.prompt_buffer = nil
      state.window = nil
    end,
    on_closed = function()
      if not state.close_reason and state.options.on_cancel then
        state.options.on_cancel()
      end
    end,
  })
  for _, value in ipairs({ buffer, state.header and state.header.buffer, prompt_buffer, prompt_header.buffer }) do
    lifecycle.track_buffer(value)
  end
  for _, value in ipairs({ window, state.header and state.header.window, prompt_window, prompt_header.window }) do
    lifecycle.track_window(value)
  end
  state.lifecycle = lifecycle
  M.mask_prompt(prompt_buffer, prompt_window)
  state.clear_prompt = function()
    if not vim.api.nvim_buf_is_valid(prompt_buffer) then
      return
    end
    vim.api.nvim_buf_set_lines(prompt_buffer, 0, -1, false, { "" })
    if vim.api.nvim_win_is_valid(prompt_window) then
      vim.api.nvim_win_set_cursor(prompt_window, { 1, 0 })
    end
  end
  state.refresh = function()
    if vim.api.nvim_buf_is_valid(buffer) then
      ui.render(buffer, M.render(state))
    end
  end
  local original_success = state.options.on_success
  state.options.on_success = function(token)
    state.close_reason = "success"
    close_windows(state)
    if original_success then
      original_success(token)
    end
  end
  local function submit_prompt()
    if state.busy then
      return
    end
    local value = vim.api.nvim_buf_get_lines(prompt_buffer, 0, 1, false)[1] or ""
    state.prompt_count = state.prompt_count + 1
    M.submit(state, value, state.options)
  end
  local function cancel()
    state.close_reason = "cancel"
    close_windows(state)
    if state.options.on_cancel then
      state.options.on_cancel()
    end
  end
  local keymap = require("proud.keymap")
  keymap.map(prompt_buffer, "i", "submit_token", submit_prompt, "Submit GitHub token")
  keymap.map(prompt_buffer, "n", "submit_token", function()
    if vim.api.nvim_buf_get_lines(prompt_buffer, 0, 1, false)[1] == "" then
      vim.cmd("startinsert")
    else
      submit_prompt()
    end
  end, "Submit GitHub token")
  keymap.map(prompt_buffer, "i", "cancel_token", function()
    vim.cmd("stopinsert")
    cancel()
  end, "Cancel credential entry")
  keymap.map(prompt_buffer, "n", "cancel_token", cancel, "Cancel credential entry")
  keymap.map(prompt_buffer, "n", "quit", cancel, "Cancel credential entry")
  keymap.map(buffer, "n", "cancel_token", cancel, "Cancel credential entry")
  keymap.map(buffer, "n", "quit", cancel, "Cancel credential entry")
  keymap.map(prompt_buffer, "n", "help", keymap.open_help, "Open help")
  keymap.map(buffer, "n", "help", keymap.open_help, "Open help")
  vim.api.nvim_set_current_win(prompt_window)
  vim.api.nvim_win_set_cursor(prompt_window, { 1, 0 })
  vim.cmd("startinsert")
  return buffer, window
end

function M.ensure(options, callback)
  options = options or {}
  if session_token and not options.force then
    if options.on_success then
      options.on_success(session_token)
    end
    callback(true, session_token)
    return
  end
  local function prompt(error)
    local state = M.create({
      token_path = M.default_token_path(options),
      error = error,
      prompt_count = options.prompt_count or 0,
    })
    state.options = vim.tbl_extend("force", options, {
      on_success = function(token)
        if options.on_success then
          options.on_success(token)
        end
        callback(true, token)
      end,
      on_cancel = function()
        if options.on_cancel then
          options.on_cancel()
        end
        callback(false, { message = "GitHub credential entry was cancelled" })
      end,
    })
    local open_prompt = options.open_prompt or M.open
    open_prompt(state, state.options)
  end
  M.resolve_candidate(options, function(token)
    if not token then
      prompt(nil)
      return
    end
    local validate = options.validate or function(candidate, done)
      local client = github.new({
        token = candidate,
        repository = options.repository,
        base_url = options.base_url,
        cwd = options.cwd,
      })
      client:get_repository(done)
    end
    validate(token, function(ok, result)
      if not ok then
        prompt(sanitize_error(result))
        return
      end
      session_token = token
      if options.on_success then
        options.on_success(token)
      end
      callback(true, token)
    end)
  end)
end

function M.reset()
  session_token = nil
end

return M
