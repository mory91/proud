# Verification

Run:

```sh
nvim --headless -u tests/minimal_init.lua -l tests/run_unit.lua
nvim --headless -u tests/minimal_init.lua -l tests/run_e2e.lua
nvim --headless -u tests/minimal_init.lua -l bench/run.lua
```

Inline `ProudDeleteLine`/`ProudAddLine` decorations (background only, so syntax colors stay; deleted lines carry the base text's treesitter colors) must be covered by unit and real-terminal E2E tests. E2E must open real files on a checked-out fixture repository, edit them, and prove the diff and thread marks follow the edit; commit snapshots must be read-only and diffed against the commit's parent. Cleanup must leave no decorations or mappings on files that stay loaded.

The real-terminal contract checks the full source text, add/delete palette, window bar and file navigation at four terminal sizes via `tests/terminal/run.sh`.
The lifecycle E2E repeatedly opens and closes the pull request's diff page through real terminal input, verifies retained heap growth/trend within `64 KiB`, and rejects retained buffers or windows.
