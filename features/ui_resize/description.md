# UI Resize

Proud's scene framework owns responsive relayout for native Neovim windows and the default borderless button style. Active buttons use `ProudAccent` as a complete purple fill with white text; inactive buttons use `ProudMuted` text on the normal UI background. Button rows are one terminal cell high and contain no drawn outline. The default top margin is `3`, leaving visible space above the top controls and panes. Rounded surfaces and workspaces subscribe to `VimResized`, recompute their geometry, and refresh rendered content at the new live width. The framework keeps rows straight, updates in-window headers/separators and outside selectors, preserves configured margins and gaps, and keeps scene panes independent.

Each scene receives a unique lifecycle identity on its tabpage, buffers, and windows. Deleting any owned buffer or closing any owned window closes the complete scene, including cases where the user presses the configured quit key before deferred cleanup runs. Deferred cleanup verifies those identity tags before touching Neovim handles, so a replacement scene cannot be closed when Neovim reuses a tabpage, window, or buffer ID.

## Related Code

- `feature.lua` exposes the resize contract and validates surface/workspace geometry.
- `lua/proud/ui/geometry.lua` owns rounded-surface and workspace layout calculations, shared by the renderer and this feature.
- `lua/proud/ui/lifecycle.lua` owns scene identity and complete buffer/window lifecycle cleanup.
- `tests/unit_spec.lua` verifies deterministic resize calculations and straight fitted views.
- `tests/e2e_spec.lua` verifies relayout, buffer-deletion cleanup, pre-cleanup quit, and replacement ownership in real Neovim windows.
- `tests/terminal/scene_lifecycle_test.exp` drives `:bd` through a pseudo-terminal and confirms replacement scenes survive stale cleanup.
- `tests/terminal/browser_size_test.exp` drives terminal size changes and checks live geometry.
- `bench/benchmark.lua` measures repeated relayout work under an explicit SLA.
