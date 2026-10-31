# Feature Contract

Proud has independently verified user-facing features. Each directory is the source of truth for that feature's behavior, implementation, tests, benchmark, and SLA.

New feature work must add all of the following before merge:

1. `description.md`
2. `feature.lua`
3. `tests/unit_spec.lua`
4. `tests/e2e_spec.lua`
5. `bench/benchmark.lua`
6. `SLA.md`
7. `verification.md`

Shared infrastructure lives in `lua/proud/`, but the rendered user behavior remains owned by the feature directory.

Before merge, run `make verify`. It includes unit and E2E coverage, real-terminal layout/palette checks at `80x24`, `100x30`, `120x40`, and `160x45`, plus timing and memory SLA benchmarks.
