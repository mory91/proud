# Performance SLA

- Workloads:
  - Render 500 expanded tree nodes with up to five sections over 48 columns.
  - Move through 500 expanded nodes through the attached `j`/`k` handler.
- Timing:
  - Render p95 at most `2 ms` across 30 measured iterations after 5 warmups.
  - Movement p95 at most `0.5 ms` across 200 measured iterations after 20 warmups.
- Memory:
  - Render maximum Lua heap delta at most `256 KiB`.
  - Movement maximum Lua heap delta at most `64 KiB`.
- Screen lifecycle: repeated sidebar/overview open-close cycles must retain at most `64 KiB` and release every temporary buffer and window.
- Failure: `bench/run.lua` exits non-zero on any timing or memory breach.
