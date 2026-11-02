# Performance SLA

- Render workload: draw the compare sidebar for 100 commits and 500 changed files (what every refresh draws: resize, selection sync). p95 at most `3 ms` across 25 measured iterations after 5 warmups; maximum Lua heap delta at most `512 KiB`. Same limits as the page's original render benchmark.
- Rebuild workload: when data changes (loading, picking a commit), rebuild the sidebar tree (Compare info, "All changes" and 100 commits, 500 files) from git data and draw it. p95 at most `4 ms`; maximum Lua heap delta at most `3 MiB`. Added with the sidebar; measured at about 2.2 ms and 1.9 MiB.
- Screen lifecycle: 20 measured compare open/close cycles after 20 warmups (checkout in a fixture repository, real file buffers); retained Lua heap growth and trend must be at most `64 KiB`, with no retained buffers or windows.
- Failure: `bench/run.lua` exits non-zero on any timing or memory breach.
