# Performance SLA

- Workload: reconstruct one standard Git patch from 2,000 GitHub file payloads.
- Timing: p95 at most `4 ms` across 30 measured iterations after 5 warmups.
- Memory: maximum Lua heap delta at most `768 KiB`.
- Failure: `bench/run.lua` exits non-zero on any timing or memory breach.
