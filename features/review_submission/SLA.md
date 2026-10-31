# Performance SLA

- Workload: render review decisions beside a 500-line review body across 42 and 78 columns.
- Timing: p95 at most `2 ms` across 30 measured iterations after 5 warmups.
- Memory: maximum Lua heap delta at most `256 KiB`.
- Screen lifecycle: repeated composer open-close cycles must retain at most `64 KiB` and release every temporary buffer and window.
- Failure: `bench/run.lua` exits non-zero on any timing or memory breach.
