# UI Themes

`proud.ui` owns named theme registration and Neovim highlight application. A theme contains one or more highlight groups and may inherit another theme:

```lua
local ui = require("proud.ui")

ui.add_theme("ocean", {
  extends = "proud-dark",
  groups = {
    ProudAccent = { fg = "#FFFFFF", bg = "#006469", bold = true },
    ProudAccentText = { fg = "#15B7B7" },
  },
})

ui.use_theme("ocean")
```

The registry API is exposed as `ui.themes`:

- `register(name, definition, options)` adds a theme. Existing names require `options.overwrite = true`.
- `replace(name, definition)` adds or replaces a theme.
- `list()` returns registered names in sorted order.
- `get(name)` returns resolved inherited highlight groups.
- `use(name)` selects and applies a theme.
- `apply(name)` applies a theme without changing the current selection when `name` is omitted.
- `current()` returns the selected theme name.

Theme names must be non-empty strings. Definitions must contain a non-empty `groups` table whose values are Neovim highlight attribute tables. Inheritance cycles and unknown themes fail before any highlights change.

## Proud Configuration

Proud registers these presets through the UI registry:

| Theme | Style |
| --- | --- |
| `proud-dark` | Neutral dark with the original purple accent |
| `proud-light` | Neutral light with a deep purple accent |
| `proud-midnight` | Blue-black with a vivid blue accent |
| `proud-ocean` | Deep teal with a cyan accent |
| `proud-forest` | Deep green with a leaf-green accent |
| `proud-sunset` | Warm dark with an orange accent |
| `proud-paper` | Warm cream with a brown accent |

Select a preset or custom theme through `setup()`:

```lua
require("proud").setup({
  ui = {
    theme = "ocean",
    themes = {
      ocean = {
        extends = "proud-dark",
        groups = {
          ProudAccent = { fg = "#FFFFFF", bg = "#006469", bold = true },
          ProudAccentText = { fg = "#15B7B7" },
        },
      },
    },
  },
})
```

Custom themes can extend any preset:

```lua
ui = {
  theme = "my-theme",
  themes = {
    ["my-theme"] = {
      extends = "proud-ocean",
      groups = {
        ProudAccent = { fg = "#FFFFFF", bg = "#7C3AED", bold = true },
        ProudAccentText = { fg = "#C4B5FD" },
      },
    },
  },
}
```

`proud.palette` holds Proud's presets: it registers built-ins, resolves `ui.themes`, applies the selected theme, and re-applies it after Neovim `ColorScheme` events.

## Palette Themes

Every built-in is a palette of 20 semantic colors. `proud.palette.derive(palette)` turns a palette into all of Proud's highlight groups, so cards, cursors, tabs and borders always match the background and accent. A custom theme can give a `palette` instead of (or as well as) `groups`. When it extends a palette theme, list only the colors that change:

```lua
ui = {
  theme = "plum",
  themes = {
    plum = {
      extends = "proud-dark",
      palette = { accent = "#9333EA", accent_text = "#D8B4FE" },
      groups = { ProudWarning = { fg = "#FACC15" } }, -- optional overrides
    },
  },
}
```

Palette fields: `background`, `panel`, `border`, `text`, `muted`, `bright`, `accent`, `on_accent`, `accent_text`, `selection`, `subtle_border`, `success`, `success_text`, `danger`, `danger_text`, `warning`, `add_fg`, `add_bg`, `delete_fg`, `delete_bg`. A palette theme that does not extend another palette theme must define all of them. Explicit `groups` always win over derived values.
