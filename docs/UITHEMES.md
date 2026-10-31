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

`proud.theme` remains Proud's palette adapter: it registers built-ins, resolves `ui.themes`, applies the selected theme, and re-applies it after Neovim `ColorScheme` events.
