return function(test)
  local ui = require("proud.ui")
  local themes = ui.themes

  themes.register("test-base", {
    groups = {
      ThemeSurface = { fg = "#EEEEEE", bg = "#101010" },
      ThemeOnly = { fg = "#123456" },
    },
  })
  themes.register("test-child", {
    extends = "test-base",
    groups = {
      ThemeSurface = { bg = "#222222" },
      ThemeChild = { fg = "#ABCDEF" },
    },
  })

  local child = themes.get("test-child")
  test.eq("#EEEEEE", child.ThemeSurface.fg, "theme inheritance preserves parent attributes")
  test.eq("#222222", child.ThemeSurface.bg, "theme inheritance applies child overrides")
  test.eq("#123456", child.ThemeOnly.fg, "theme inheritance includes parent-only groups")
  child.ThemeSurface.bg = "#999999"
  test.eq("#222222", themes.get("test-child").ThemeSurface.bg, "theme reads return defensive copies")
  test.contains(themes.list(), "test-base")
  test.contains(themes.list(), "test-child")

  local duplicate_ok, duplicate_error = pcall(themes.register, "test-base", {
    groups = { ThemeSurface = { bg = "#000000" } },
  })
  test.truthy(not duplicate_ok, "duplicate theme registration requires explicit replacement")
  test.contains(duplicate_error, "already registered")
  themes.replace("test-base", {
    groups = {
      ThemeSurface = { fg = "#EEEEEE", bg = "#101010" },
      ThemeOnly = { fg = "#123456" },
    },
  })

  themes.register("test-cycle-a", { extends = "test-cycle-b", groups = { ThemeCycle = {} } })
  themes.register("test-cycle-b", { extends = "test-cycle-a", groups = { ThemeCycle = {} } })
  local cycle_ok, cycle_error = pcall(themes.get, "test-cycle-a")
  test.truthy(not cycle_ok, "theme inheritance cycles are rejected")
  test.contains(cycle_error, "inheritance cycle")

  themes.use("test-base")
  test.eq("test-base", themes.current())
  test.eq("test-base", ui.current_theme())
  themes.use("test-child")
  test.eq("test-child", ui.current_theme())
  test.eq(true, vim.o.termguicolors, "theme application enables true-color highlights")
  local child_highlight = vim.api.nvim_get_hl(0, { name = "ThemeChild", link = false })
  test.eq("#ABCDEF", ("#%06X"):format(child_highlight.fg), "selected themes apply real Neovim highlights")
  ui.use_theme("test-base")
  local removed_highlight = vim.api.nvim_get_hl(0, { name = "ThemeChild", link = false })
  test.eq(nil, removed_highlight.fg, "switching themes clears groups no longer provided")

  local invalid_ok, invalid_error = pcall(themes.register, "", { groups = { ThemeInvalid = {} } })
  test.truthy(not invalid_ok, "empty theme names are rejected")
  test.contains(invalid_error, "non-empty string")
  invalid_ok, invalid_error = pcall(themes.register, "test-invalid", {})
  test.truthy(not invalid_ok, "themes without highlight groups are rejected")
  test.contains(invalid_error, "at least one highlight group")

  local proud_theme = require("proud.palette")
  local presets = {
    "proud-dark",
    "proud-forest",
    "proud-light",
    "proud-midnight",
    "proud-ocean",
    "proud-paper",
    "proud-sunset",
  }
  test.eq(presets, proud_theme.builtin_names(), "Proud registers its built-in theme presets")
  local preset_backgrounds = {}
  for _, name in ipairs(presets) do
    local groups = themes.get(name)
    test.eq(25, #vim.tbl_keys(groups), name .. " resolves a complete Proud highlight set")
    test.truthy(preset_backgrounds[groups.ProudBackground.bg] == nil, name .. " has a distinct background palette")
    preset_backgrounds[groups.ProudBackground.bg] = name
    proud_theme.setup({ theme = name })
    local accent = vim.api.nvim_get_hl(0, { name = "ProudAccent", link = false })
    test.eq(groups.ProudAccent.bg, ("#%06X"):format(accent.bg), name .. " applies its preset accent")
  end
  proud_theme.setup({
    theme = "proud-test",
    themes = {
      ["proud-test"] = {
        extends = "proud-dark",
        groups = {
          ProudAccent = { bg = "#123456" },
        },
      },
    },
  })
  local custom = proud_theme.groups()
  test.eq("#123456", custom.ProudAccent.bg, "Proud custom themes can override semantic groups")
  test.eq("#101828", custom.ProudBackground.bg, "Proud custom themes inherit the selected base palette")
  local accent_highlight = vim.api.nvim_get_hl(0, { name = "ProudAccent", link = false })
  test.eq("#123456", ("#%06X"):format(accent_highlight.bg), "Proud applies custom theme values to Neovim")
  local tabline = require("proud.ui.tabline")
  local tabline_before = vim.o.tabline
  proud_theme.apply()
  test.eq(tabline_before, vim.o.tabline, "theme application no longer touches the tabline")
  vim.o.tabline = "%f user tabline"
  tabline.enable()
  test.eq(tabline.expression, vim.o.tabline, "tabline.enable installs the Proud tabline")
  test.contains(tabline.render(), "%#ProudPanel#%=", "the tabline renders Proud tab labels")
  tabline.disable()
  test.eq("%f user tabline", vim.o.tabline, "tabline.disable restores the user's tabline")
  vim.o.tabline = tabline_before
  local ui_theme = require("proud.ui.theme")
  vim.o.termguicolors = false
  ui_theme.set_manage_termguicolors(false)
  proud_theme.apply()
  test.eq(false, vim.o.termguicolors, "termguicolors can be left to the user")
  ui_theme.set_manage_termguicolors(true)
  proud_theme.apply()
  test.eq(true, vim.o.termguicolors, "termguicolors is managed by default")

  proud_theme.setup({ theme = "proud-dark" })
  test.eq("#101828", proud_theme.groups().ProudBackground.bg, "tests restore the default Proud theme")

  local palette = require("proud.palette")
  palette.setup({
    theme = "test-plum",
    themes = {
      ["test-plum"] = {
        extends = "proud-dark",
        palette = { accent = "#9333EA", background = "#000000" },
        groups = { ProudWarning = { fg = "#FACC15" } },
      },
    },
  })
  local plum = palette.groups()
  test.eq("#9333EA", plum.ProudAccent.bg, "palette themes derive the accent fill")
  test.eq("#000000", plum.ProudCard.bg, "derived card background follows the palette background")
  test.eq("#000000", plum.ProudCursorHidden.fg, "hidden cursor follows the palette background")
  test.eq("#EAECF0", plum.ProudText.fg, "unchanged palette fields come from the extended theme")
  test.eq("#FACC15", plum.ProudWarning.fg, "explicit groups override derived values")
  local missing_ok, missing_error = pcall(palette.setup, {
    theme = "test-partial",
    themes = { ["test-partial"] = { palette = { accent = "#000000" } } },
  })
  test.truthy(not missing_ok, "a standalone palette must define every field")
  test.contains(missing_error, "missing", "missing palette fields are reported")
  palette.setup({ theme = "proud-dark" })
end
