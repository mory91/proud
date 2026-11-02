# Performance SLA

- Workload: the thread window's text for a long conversation. 50 comments with two-paragraph bodies (about 400 characters each), wrapped to the 84-cell window, with the quoted line, author and pending tags and the reply header. This runs when the window opens and after every reply or resolve.
- Timing: p95 at most `2 ms` across 25 measured iterations.
- Memory: maximum Lua heap delta at most `512 KiB`.
- Failure: `bench/run.lua` exits non-zero on any timing or memory breach.

Measured when introduced: p95 about 1.2 ms, about 210 KiB.
