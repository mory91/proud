# GitHub API SDK

Provide Proud's only GitHub integration surface as an asynchronous Lua SDK. The SDK owns GitHub REST and GraphQL request construction, deterministic pagination, authentication, repository discovery, pull request metrics, check-run durations, diff retrieval, review comments, review submission, and issue comments. Check aggregation uses the pull request's GraphQL `statusCheckRollup`, including both `CheckRun` and `StatusContext` nodes, as the canonical PR-page-compatible source. REST head SHA and GitHub-generated merge SHA check runs and commit statuses remain fallbacks because actions may attach outside the PR rollup; overlapping runs are deduplicated by GitHub database ID. Pull request search uses one cursor-paginated GraphQL request for review-thread totals and diff counts without requesting any pull request description bodies. A separate lightweight GraphQL method loads one pull request's first message only when its preview needs it. It accepts an injectable transport for deterministic tests and uses `curl` through `vim.system` for production HTTP.

## Related Code

- `feature.lua` implements the SDK and its default secure transport.
- `tests/unit_spec.lua` independently verifies requests, cursor variables, omitted list descriptions, GraphQL search metrics, REST pagination, authentication, errors, patch reconstruction, review submission, and repository parsing.
- `tests/e2e_spec.lua` verifies asynchronous pull request enrichment inside Neovim, GraphQL-only checks, mixed check-context types, overview delivery, and GraphQL/REST deduplication.
- `bench/benchmark.lua` covers patch construction from 2,000 GitHub file payloads.
