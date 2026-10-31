# Verification

Run:

```sh
nvim --headless -u tests/minimal_init.lua -l tests/run_unit.lua
nvim --headless -u tests/minimal_init.lua -l tests/run_e2e.lua
nvim --headless -u tests/minimal_init.lua -l bench/run.lua
```

Full-file reconstruction and inline `ProudDelete`/`ProudAdd` coloring must be covered by unit and real-terminal E2E tests. The scene must open before PR, patch, and thread callbacks; each response must hydrate the same state safely. Thread mutations must be covered by unit tests, their keyboard path must be covered by E2E, and large file/conversation state must remain inside the feature's memory SLA.

The real-terminal contract checks the full-file source rows, add/delete palette, file list, thread status, comment authors, and reply actions at four terminal sizes via `tests/terminal/run.sh`.
The lifecycle E2E repeatedly opens and closes this screen through real terminal input, verifies retained heap growth/trend within `64 KiB`, and rejects retained buffers or windows.
