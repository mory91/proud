# Editable Diff

Review a pull request in the code itself. Opening the diff checks out the PR branch **in place** in the current repository (`origin/<head>` as a local tracking branch, or `pull/<n>/head` as `pr-<n>` for forks) and computes the merge base with the target branch, which is how GitHub computes a PR diff. If git fails (uncommitted changes in the way, a failed fetch, a conflict), the scene shows git's own message and nothing else is attempted.

Each changed file opens as the **real file** in a normal, editable buffer, one file at a time, with Neovim's own line numbers, sign column, syntax and LSP. The file is compared live with its merge-base version using Neovim's built-in diff engine: added and changed lines are highlighted with a `+` sign, and deleted lines appear as virtual lines at their old position. Editing updates the diff as you type, and saving writes the file.

Review threads show as `◆` (open) or `◇` (resolved) signs with an end-of-line preview of the first comment. They are extmarks, so they move with the text when you edit. A window bar shows `base → head`, the file path, live `[+added −deleted]` counts and the file's position (`1 / 5`); the tab is titled `#N diff · single-pane`.

`]f` / `[f` switch files and `]t` / `[t` jump to threads. No `r`, `R` or `q` mappings are placed on real files (in Neovim those are replace, Replace mode and macro recording); reading whole threads, replying and resolving come with the thread window. Closing the scene removes every decoration and mapping from your files and unloads the files it opened, except those with unsaved edits or shown elsewhere.

## Related Code

- `feature.lua` checks out the branch (`lua/proud/git.lua`), opens real files, attaches `ui.inline_diff`, and places thread signs and previews.
- `lua/proud/ui/inline_diff.lua` draws a live diff on any buffer with `vim.diff`.
- `lua/proud/fixture_repo.lua` builds a real fixture repository (with a local origin) for the demo, tests and benchmarks.
- `tests/unit_spec.lua` verifies the window bar, status and error views, thread previews, thread data, and inline diff decorations.
- `tests/e2e_spec.lua` verifies the in-place checkout, real editable files, live re-diffing on edit, thread signs that follow edits, file and thread navigation, cleanup on close, git error display, and delayed PR/thread hydration.
- `bench/benchmark.lua` covers the live diff of a 1,200-line file with 600 changed lines and 1,000 threads.
- `tests/memory_leak_spec.lua` verifies repeated real-screen open/close lifecycle remains within the feature's memory and resource SLA.
