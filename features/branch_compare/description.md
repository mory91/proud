# Branch Compare

Compare local branches without a pull request. The summary and changes panes appear immediately while Git commands resolve, then hydrate in place. Reviewer interactions remain authoritative during loading: swapping base and head reverses the eventual ahead/behind counts without rebuilding state. The view summarizes ahead/behind counts, commits, changed files, and local notes, and supports two-dot and three-dot modes.

## Related Code

- `feature.lua` maintains comparison state and renders the offline Git view.
- `tests/unit_spec.lua` verifies totals, swapping, and compare modes.
- `tests/e2e_spec.lua` verifies keyboard-driven branch swapping and UI-first loading during asynchronous Git commands.
- `bench/benchmark.lua` covers 100 commits and 500 changed files.
- `tests/memory_leak_spec.lua` verifies repeated real-screen open/close lifecycle remains within the feature's memory and resource SLA.
