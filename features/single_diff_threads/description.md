# Single-Pane Full-File Diff

Read one file at a time in a single full-width pane: the complete file with deleted rows inserted and additions and deletions colored across the whole row. Each row shows the old and new line numbers, then a sign column with `+` or `-`, replaced by `◆` for an open review thread or `◇` for a resolved one. Open threads preview their first comment after the end of the line (`◆ dev-lee: attempt is already…`); resolved threads show `◇ resolved`. The cursor row is highlighted and its line numbers are bold.

A window bar at the top of the pane shows `base → head`, the file path, the file's `[+added −deleted]` counts and its position (`1 / 5`). The scene title is `#N diff · single-pane`. `]f` and `[f` switch files; `]t` and `[t` move to the next or previous thread, switching file when needed and putting the cursor on the thread's row. `r` replies to and `R` resolves the selected thread.

The diff opens immediately with loading content while pull metadata, patch data and review threads hydrate independently. Full-file content is loaded lazily for the selected file, so large pull requests do not materialize every source file at once.

Reading whole threads and replying in place come with the thread window (design screen 4), tracked separately.

## Related Code

- `feature.lua` overlays patch rows onto full-file source and combines them with thread conversations and review actions.
- `tests/unit_spec.lua` verifies full-file reconstruction, line-number gutters, thread markers and end-of-line previews, the window bar, inline diff colors, replies, resolution, and thread navigation.
- `tests/e2e_spec.lua` verifies the single pane and window bar, keyboard-driven file and thread navigation, the cursor row, thread resolution, and independent delayed PR/patch/thread hydration in Neovim.
- `bench/benchmark.lua` covers 1,200 full-file lines and 1,000 threads with three comments each.
- `tests/memory_leak_spec.lua` verifies repeated real-screen open/close lifecycle remains within the feature's memory and resource SLA.
