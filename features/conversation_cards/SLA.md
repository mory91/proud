# Performance SLA

- Workload: lay out 100 mixed-depth conversation cards.
- Timing: p95 at most `2 ms` across 30 measured iterations after 5 warmups.
- Memory: maximum Lua heap delta at most `512 KiB`.
- Lifecycle: 20 mount/unmount cycles retain at most `64 KiB` and release every card buffer and window.
