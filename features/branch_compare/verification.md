# Verification

Run:

```sh
nvim --headless -u tests/minimal_init.lua -l tests/run_unit.lua
nvim --headless -u tests/minimal_init.lua -l tests/run_e2e.lua
nvim --headless -u tests/minimal_init.lua -l bench/run.lua
```

Branch state must be verified independently of Git commands so compare rendering is deterministic. E2E must prove both panes open with loading content before Git callbacks resolve. Unit tests must prove that a swap made during loading reverses the eventual ahead/behind counts. The provider integration remains asynchronous and is not included in the render benchmark.

The real-terminal contract checks compare mode, refs, ahead/behind state, commit IDs, file statuses, additions/deletions, notes, and key hints via `tests/terminal/run.sh`.
The lifecycle E2E repeatedly opens and closes this screen through real terminal input, verifies retained heap growth/trend within `64 KiB`, and rejects retained buffers or windows.
