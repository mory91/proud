# GitHub Credentials

Gate live GitHub scenes behind validated, reusable authentication. When no usable token is available, a centered two-pane Proud page explains the missing credential and provides a focused, one-line token prompt directly below it. Tokens are masked while typed in that page; command-line input is never used. Invalid tokens show an actionable error in the same page and clear the rejected value. A successful token is validated against the configured repository, saved with owner-only permissions, cached for later scenes in the current Neovim session, and reused on later launches.

## Related Code

- `feature.lua` resolves, validates, securely persists, and prompts for GitHub tokens.
- `tests/unit_spec.lua` verifies normalization, precedence, secure persistence, error handling, and reuse.
- `tests/e2e_spec.lua` verifies the centered modal and keyboard workflow in Neovim.
- `bench/benchmark.lua` covers modal rendering for 100 validation errors.
- `tests/memory_leak_spec.lua` verifies repeated real-screen open/close lifecycle remains within the feature's memory and resource SLA.
