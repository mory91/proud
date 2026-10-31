# Performance SLA

- Workload: render 80 mappings across 20 groups plus commands.
- Timing: p95 at most `1 ms` across 50 measured iterations after 10 warmups.
- Memory: maximum Lua heap delta at most `128 KiB`.
- Screen lifecycle: 20 measured Help open/close cycles after 20 warmups; retained Lua heap growth and trend must be at most `64 KiB`, with no retained buffers or windows.
- Failure: `bench/run.lua` exits non-zero on any timing or memory breach.
