# Verification

Run:

```sh
nvim --headless -u tests/minimal_init.lua -l tests/run_unit.lua
nvim --headless -u tests/minimal_init.lua -l tests/run_e2e.lua
nvim --headless -u tests/minimal_init.lua -l bench/run.lua
./tests/terminal/run.sh
```

Credential behavior must be verified without printing or persisting rejected tokens. Tests cover environment precedence, owner-only file permissions, in-page prompt focus and concealment, idempotent prompt-mask setup, rejected-value clearing, disabled prompt undo history, invalid submission recovery, successful replacement, session reuse, and later-launch reuse. The real-terminal contract types into the centered prompt pane in the same isolated Neovim binary used for UI workflows and confirms that later launches reuse the saved token without opening the prompt.

The performance contract covers both validation-error rendering and masked prompt refreshes. The lifecycle E2E repeatedly opens and closes the credential modal through real terminal input, verifies the heap growth/trend SLA, and rejects retained buffers or windows. `bench/run.lua` enforces the feature SLA and exits non-zero on a timing or memory breach.
The lifecycle E2E repeatedly opens and closes this screen through real terminal input, verifies retained heap growth/trend within `64 KiB`, and rejects retained buffers or windows.
