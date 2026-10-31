# Verification

Run:

```sh
nvim --headless -u tests/minimal_init.lua -l tests/run_unit.lua
nvim --headless -u tests/minimal_init.lua -l tests/run_e2e.lua
./tests/terminal/run.sh
nvim --headless -u tests/minimal_init.lua -l bench/run.lua
```

Unit tests enforce the five-section maximum, independent spacing profiles, one-line API text normalization, nested visibility rules, direct expand/collapse operations, layout snapshot restoration, contextual activation, header statuses, and composed commit/file/check rows. Check tests pin `Checks 4 of 5 passing`, the exact aligned `✓ lint                 18s` and `✗ e2e / robot-studio   6m 40s` rows, and their semantic colors. E2E tests use actual Neovim windows and keyboard input to navigate entries without structural repainting, expand and collapse branches while retaining one full refresh, preserve those choices through async overview hydration, mark a selected file viewed, and open its diff callback. Real-terminal tests repeat the check listing, navigation, and directional branch controls at multiple viewport sizes. The overview integration remains a separate two-pane Vim workspace at every supported terminal size. Memory tests repeatedly open and close the sidebar screen. Benchmarks render 500 visible file/check entries and exercise 500-node movement through the attached keyboard handler under their declared p95 and heap limits.
