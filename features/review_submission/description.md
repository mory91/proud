# Review Submission

Proud can submit a pull request review with `Comment`, `Approve`, or `Request changes`. The scene uses two native panes: review decisions on the left and a real editable review body on the right. Decision controls use the shared solid-fill button style with only the selected decision highlighted in purple. Body text is never displayed as keyboard instructions or command output.

Submission is asynchronous and uses the GitHub REST API through the project SDK. Comment and request-changes reviews require a non-empty body; approvals may omit the body. Failed validation remains in the scene so the reviewer can correct it without losing the draft.

## Related Code

- `feature.lua` owns decision state, body editing, rendering, validation, and asynchronous submission.
- `features/github_api/feature.lua` owns the `/pulls/{number}/reviews` request contract.
- `lua/proud/provider.lua` exposes the operation to scenes without another GitHub interface.
- `tests/unit_spec.lua` verifies validation, state transitions, rendering, and callbacks.
- `tests/e2e_spec.lua` verifies keyboard-driven submission in a real Neovim workspace.
- `tests/memory_leak_spec.lua` verifies repeated composer lifecycles remain bounded.
- `bench/benchmark.lua` measures decision rendering with a long review body.
