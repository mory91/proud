# Performance SLA

- Workload 1: render 100 credential modals carrying validation errors. p95 at most `2 ms` and maximum Lua heap delta at most `256 KiB`.
- Workload 2: configure syntax masking for 100 one-line credential prompts. p95 at most `2 ms` and maximum Lua heap delta at most `128 KiB`.
- Samples: 40 measured iterations after 8 warmups for each workload.
- Screen lifecycle: 20 measured open/close cycles after 20 warmups; retained Lua heap growth and trend must be at most `64 KiB`, with no retained buffers or windows.
- Failure: `bench/run.lua` exits non-zero on any timing or memory breach.
