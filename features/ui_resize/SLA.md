# Performance SLA

- Workload: perform 50 rounded-surface relayouts over 100 rendered rows at 160x45 and 80x24.
- Timing: p95 at most `4 ms` across 30 measured iterations after 5 warmups.
- Memory: maximum Lua heap delta at most `512 KiB`.
- Failure: `bench/run.lua` exits non-zero on any timing or memory breach.
