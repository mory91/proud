# Performance SLA

- Workload: render 200 files, 250 description lines, commits, and checks.
- Timing: p95 at most `4 ms` across 30 measured iterations after 5 warmups.
- Memory: maximum Lua heap delta at most `768 KiB`.
- Screen lifecycle: 20 measured overview open/close cycles after 20 warmups; retained Lua heap growth and trend must be at most `64 KiB`, with no retained buffers or windows.
- Failure: `bench/run.lua` exits non-zero on any timing or memory breach.
