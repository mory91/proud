# Real Terminal E2E

These tests launch the isolated Neovim binary inside a real pseudo-terminal using `expect`. They send actual keys and inspect Neovim's terminal redraw output, including true-color ANSI sequences.

Run:

```sh
./tests/terminal/run.sh
```

The test uses a temporary Git repository and never contacts GitHub. It also verifies full source text in the diff buffer, true-color inline deletion/addition highlighting, overview-to-diff navigation, `<CR>` file selection in the diff workspace, and semantic highlight groups in every workspace scene.
