# Performance Policy

Proud treats performance SLAs as behavioral contracts, not aspirational targets.

## Rules

- Every user-facing feature has one deterministic timing and memory benchmark.
- The GitHub API SDK has its own transformation benchmark and fixed SLA.
- Credential discovery and modal rendering have their own fixed workloads and SLA.
- Unit and E2E verification must pass before benchmark results are considered valid.
- Benchmarks use fixed synthetic workloads, warmups, at least 15 measured iterations, p50/p95 timing, and maximum Lua heap delta.
- Fixture creation is outside the timed and measured region.
- Render functions return a checksum-affecting result that is consumed by the benchmark.
- A failed timing or memory SLA makes `make verify` fail.
- SLA changes must update the feature's `SLA.md` and `README.md` table in the same patch.

## Measurement

Timing uses `vim.uv.hrtime()` or `vim.loop.hrtime()`. Memory uses `collectgarbage("count")` immediately before and after each measured render after a full collection. The reported `max_memory_kb` is the largest per-iteration Lua heap delta.

The benchmark measures deterministic feature model and render work. Asynchronous GitHub and Git I/O is outside render SLAs because network and disk latency are externally variable; that integration is covered by unit seams and headless feature workflows.
