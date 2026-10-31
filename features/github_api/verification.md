# Verification

Run the SDK in isolation before provider or UI tests:

```sh
nvim --headless -u tests/minimal_init.lua -l tests/run_github_sdk.lua
```

Then run the complete project gates:

```sh
./scripts/verify.sh
```

The SDK contract is tested through an injected transport, so endpoint, pagination, authentication, and failure behavior do not depend on network availability. The pull request page contract uses one cursor-paginated GraphQL search request, requests no description bodies, returns `issueCount` and `pageInfo`, and preserves raw `reviewThreads.totalCount`, `additions`, `deletions`, labels, requested reviewers, and latest reviews. The description contract uses a separate body-only GraphQL request. Pull-request enrichment loads REST reviews, review comments, and issue comments alongside files, commits, checks, and statuses; review comments retain their review-parent and reply links so inline messages render even when a review summary body is empty. Check tests use the PR-level GraphQL `statusCheckRollup` as the canonical source, paginate its contexts, accept both `CheckRun` and `StatusContext`, still work when every REST check endpoint is empty, and verify `Checks 1 of 3 passing` with children reaches the overview sidebar. A separate aggregation case gives GraphQL and REST the same GitHub database ID and requires one displayed check. REST check-run pagination accepts GitHub's `{ total_count, check_runs }` response shape and uses `total_count` to stop at the final page. Check-run durations are formatted from `started_at` and `completed_at`, including `18s`, `6m 40s`, and `1h 02m` boundaries. Provider tests verify partial `check_errors` remain available while normal checks are normalized. Review submission posts normalized `COMMENT`, `APPROVE`, and `REQUEST_CHANGES` events to `/pulls/{number}/reviews`, rejects invalid events and empty non-approval bodies before transport, and preserves the returned review result. The real-terminal suite renders normalized `3 threads`, `1 thread`, and `no threads` cases plus GraphQL-only source-backed checks, reviewer, label, summary, and conversation data, including empty-review inline messages, in actual Neovim windows. The SDK benchmark enforces its own timing and memory SLA.

Run the production HTTP transport against the public GitHub REST API independently with:

```sh
make github-sdk-live
```

Set `PROUD_GITHUB_REPOSITORY`, `PROUD_GITHUB_API_URL`, and token variables when testing an authenticated or Enterprise repository.
