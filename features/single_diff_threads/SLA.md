# Performance SLA

- Workload: render 1,200 full-file lines with inline patch rows plus 1,000 threads with 3,000 comments.
- Timing: p95 at most `8 ms` across 15 measured iterations after 20 warmups.
- Memory: maximum Lua heap delta at most `2 MiB`.
- Screen lifecycle: 20 measured full-file diff open/close cycles after 20 warmups; retained Lua heap growth and trend must be at most `64 KiB`, with no retained buffers or windows.
- Failure: `bench/run.lua` exits non-zero on any timing or memory breach.
