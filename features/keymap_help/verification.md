# Verification

Run:

```sh
nvim --headless -u tests/minimal_init.lua -l tests/run_unit.lua
nvim --headless -u tests/minimal_init.lua -l tests/run_e2e.lua
nvim --headless -u tests/minimal_init.lua -l bench/run.lua
```

Help content is part of the feature contract because missing mappings are user-facing regressions. Unit coverage verifies configured overrides appear in Help, including preview focus and return-to-list actions; E2E verifies Help lifecycle; and terminal coverage rejects shortcut legends in every non-Help scene. The render path has a tight latency and heap SLA.

The real-terminal contract checks semantic colors for section headings, keycaps, command names, descriptions, and runtime notes via `tests/terminal/run.sh`.
The lifecycle E2E repeatedly opens and closes this screen through real terminal input, verifies retained heap growth/trend within `64 KiB`, and rejects retained buffers or windows.
