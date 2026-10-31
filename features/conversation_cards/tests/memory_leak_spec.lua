return function(test)
  local feature = require("proud.loader").load("conversation_cards")
  vim.cmd("vnew")
  local host_window = vim.api.nvim_get_current_win()
  local host_buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(host_buffer, 0, -1, false, vim.fn["repeat"]({ "" }, 30))
  vim.api.nvim_win_set_width(host_window, 72)
  vim.api.nvim_win_set_height(host_window, 20)
  local specs = feature.layout({
    { id = "root", author = "reviewer", age = "1h", body = "Root message" },
    { id = "reply", depth = 1, author = "author", age = "20m", body = "Reply message" },
  }, { width = 70, margin = 0, start_row = 4 })

  for _ = 1, 6 do
    local state = feature.create({ host_window = host_window })
    feature.sync(state, specs)
    feature.close(state)
  end
  collectgarbage("collect")
  collectgarbage("collect")
  local before = collectgarbage("count")
  local buffers_before = #vim.api.nvim_list_bufs()
  for _ = 1, 20 do
    local state = feature.create({ host_window = host_window })
    feature.sync(state, specs)
    feature.close(state)
  end
  collectgarbage("collect")
  collectgarbage("collect")
  local growth = collectgarbage("count") - before
  test.truthy(growth <= 64, "native card open/close lifecycle stays within 64 KiB")
  test.eq(buffers_before, #vim.api.nvim_list_bufs(), "native card lifecycle releases every buffer")
  vim.cmd("silent! bwipeout!")
end
