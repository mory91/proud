# Verification

Run:

```sh
nvim --headless -u tests/minimal_init.lua -l tests/run_unit.lua
nvim --headless -u tests/minimal_init.lua -l tests/run_e2e.lua
nvim --headless -u tests/minimal_init.lua -l bench/run.lua
./tests/terminal/run.sh
```

Conversation cards must use native `nvim_open_win()` rectangles with rounded borders, never render card border glyphs into content buffers, preserve author/age/decision highlight semantics, place replies beneath and inset from roots, follow host-window scrolling and resizing, and release every owned buffer/window. Root cards must use `ProudBackground` and replies must use the subtle `ProudPanel` shade; the real-terminal suite checks both window mappings and exact theme values. Partially visible cards remain mounted until complete viewport exit; their buffers contain only intersecting rows and omit only the rounded edge that is outside the host window. Unit tests cover top clipping, bottom clipping, and complete exit, while the real-terminal metadata contract scrolls a card through the same states in an actual Neovim terminal. The lifecycle E2E keeps heap growth within `64 KiB`. The 100-card layout benchmark enforces p95 at most `2 ms` and maximum Lua heap delta at most `512 KiB`.
