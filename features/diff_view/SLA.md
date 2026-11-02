# Performance SLA

- Workload: the live diff for one file. Diff a 1,200-line buffer against its merge base (600 changed lines, so 600 highlighted lines and 600 deleted virtual lines) and draw the decorations, color the deleted lines in view with the base text's treesitter syntax (cold caches; the base is parsed asynchronously beforehand), then place 1,000 thread signs with end-of-line previews. The diff part runs again, debounced, on every edit.
- Timing: p95 at most `8 ms` across 15 measured iterations.
- Memory: maximum Lua heap delta at most `2 MiB`.
- Screen lifecycle: 20 measured open/close cycles of the pull request diff page (checkout in a fixture repository, real file buffers) after warmups; retained Lua heap growth and trend must be at most `64 KiB`, with no retained buffers or windows.
- Failure: `bench/run.lua` exits non-zero on any timing or memory breach.

The limits are unchanged from the previous rendered diff (1,200 rows + 1,000 threads); the workload changed with the feature.
