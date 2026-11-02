# Verification

Run:

```sh
nvim --headless -u tests/minimal_init.lua -l tests/run_unit.lua
nvim --headless -u tests/minimal_init.lua -l tests/run_e2e.lua
nvim --headless -u tests/minimal_init.lua -l bench/run.lua
```

The sidebar must be verified from plain state so its rendering is deterministic. E2E must run on a fixture repository (never the repository running the tests): the page opens with placeholders before git finishes, checks out the head, and commit selection must show only that commit's files against its parent. Hiding the sidebar must never close the page.

The real-terminal contract checks the sidebar's colors, the diff pane's window bar and inline diff, file navigation, the sidebar toggle and swapping via `tests/terminal/run.sh`.
The lifecycle E2E repeatedly opens and closes this screen through real terminal input, verifies retained heap growth/trend within `64 KiB`, and rejects retained buffers or windows.
