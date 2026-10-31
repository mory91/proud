# UI Content

`require("proud.ui")` provides shared text wrapping and content-box rendering:

```lua
local ui = require("proud.ui")

local body_lines = ui.wrap_text(value, inner_width)
local padded_lines = ui.content_lines(value, {
  width = pane_width,
  padding = 2,
  wrap = true,
})

local text_frame = ui.open_text_frame(window, { padding = 2 })
```

`wrap_text(value, width, options)` returns logical lines. By default it follows Neovim's global `wrap` setting (`vim.go.wrap`). In wrapped mode it constrains lines to the requested width, preserves explicit newlines, collapses horizontal whitespace only when a source line must wrap, and splits unbreakable tokens by display-cell width. In non-wrapped mode it preserves each complete source line for horizontal navigation. Explicit `{ wrap = true }` or `{ wrap = false }` overrides the Neovim default.

`content_lines(value, options)` applies `options.padding` to both sides. It follows Neovim's global `wrap` setting by default. Wrapped rows fit `options.width` exactly; non-wrapped rows retain the complete padded logical line so Neovim's normal horizontal scrolling and cursor navigation can reveal content beyond the viewport.

`open_text_frame(window, options)` keeps the configured left and right margins fixed while native horizontal navigation moves complete non-wrapped rows behind them. Workspace panes create and resize this frame automatically from `view.padding`; its `set_padding`, `resize`, and `close` methods support standalone windows and lifecycle cleanup.

The shared API fits content before buffer rendering and constrains its visible viewport at the window layer, so margins stay stable regardless of the window's native `wrap` state.

## Module Layout

`require("proud.ui")` loads `lua/proud/ui/init.lua`, which re-exports the stable API. Callers should use that entry point; the modules behind it may move.

| Module | Responsibility |
| --- | --- |
| `ui/text.lua` | Display width, `fit`, `wrap_text`, `content_lines` |
| `ui/render.lua` | Writing views (lines + highlights) into buffers |
| `ui/window.lua` | Buffer preparation, window decoration, cursor placement |
| `ui/lifecycle.lua` | Scene identity and buffer/window cleanup |
| `ui/text_frame.lua` | Fixed side margins over horizontally scrolling content |
| `ui/header.lua` | In-pane header row and separator |
| `ui/selector.lua` | Button row layout and the source selector bar |
| `ui/geometry.lua` | Pure surface and workspace layout math |
| `ui/config.lua` | Configured margins and gap |
| `ui/surface.lua` | Rounded two-pane surface |
| `ui/workspace.lua` | Native split workspaces |
| `ui/float.lua` | Floating-window primitive: one placement drives open and reposition |
| `ui/modal.lua` | Centered modal float |
| `ui/theme.lua` | Theme registry |
