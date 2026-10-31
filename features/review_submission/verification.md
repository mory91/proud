# Verification

Run:

```sh
nvim --headless -u tests/minimal_init.lua -l tests/run_unit.lua
nvim --headless -u tests/minimal_init.lua -l tests/run_e2e.lua
./tests/terminal/run.sh
nvim --headless -u tests/minimal_init.lua -l bench/run.lua
```

Unit tests enforce decision normalization, required review bodies, success and failure callbacks, and semantic button highlighting. E2E tests drive the controls and editable body through actual Neovim buffers. Real-terminal tests exercise the complete submission flow, and lifecycle tests repeatedly open and close the composer. The fixed benchmark enforces the declared p95 and heap limits.
