if vim.g.loaded_proud == 1 then
  return
end
vim.g.loaded_proud = 1

require("proud").setup()

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("ProudTheme", { clear = true }),
  callback = function()
    require("proud.theme").apply()
  end,
})
