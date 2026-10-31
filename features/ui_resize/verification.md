# Verification

Run:

```sh
nvim --headless -u tests/minimal_init.lua -l tests/run_unit.lua
nvim --headless -u tests/minimal_init.lua -l tests/run_e2e.lua
./tests/terminal/run.sh
nvim --headless -u tests/minimal_init.lua -l bench/run.lua
```

The resize, button, and scene-lifecycle contract covers both rounded floating surfaces and native split workspaces. Unit tests assert width/height margins, pane gap, exact row widths, one-row borderless buttons, full-segment active/inactive fills, default highlight groups, and identity-guarded deferred cleanup. E2E tests open actual Neovim windows, delete an owned buffer, press quit before deferred cleanup runs, and prove a replacement scene is not touched by old cleanup. The real-terminal suite launches the isolated Neovim binary in a pseudo-terminal, drives `:bd` through keyboard input, verifies the whole scene closes, changes live dimensions, fires the public `VimResized` path, and verifies the framework responds without reopening the scene. Benchmarks repeat layout calculations and fitted rendering under the declared p95 and heap SLAs.

The contract intentionally verifies both shrink and restore, because stale geometry is the most common resize regression. Every scene's `on_resize` callback is responsible for re-rendering feature content at its new live pane widths; the framework never relies on a stale initial width.
