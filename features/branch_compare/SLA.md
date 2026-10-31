# Performance SLA

- Workload: render 100 commits and 500 changed files.
- Timing: p95 at most `3 ms` across 25 measured iterations after 5 warmups.
- Memory: maximum Lua heap delta at most `512 KiB`.
- Screen lifecycle: 20 measured compare open/close cycles after 20 warmups; retained Lua heap growth and trend must be at most `64 KiB`, with no retained buffers or windows.
- Failure: `bench/run.lua` exits non-zero on any timing or memory breach.
