# Isolated Test Environment

Proud includes a local Neovim test environment in `test-env/`. The executable and runtime are copied from `PROUD_SOURCE_NVIM`, while configuration, plugins, state, shada, and cache are redirected to `test-env/state/`.

This is intentionally lighter than compiling Neovim from source. It provides a separate binary and runtime without changing Homebrew, the system PATH, or the user's normal Neovim installation.

## Setup

```sh
./scripts/setup_proud_test_env.sh
```

Use a different source installation when needed:

```sh
PROUD_SOURCE_NVIM=/path/to/nvim ./scripts/setup_proud_test_env.sh
```

## Live Repository

```sh
PROUD_GIT_REPO=/path/to/live/checkout ./scripts/run_proud_test_nvim.sh
```

The Git path is resolved to its top-level directory and becomes Neovim's working directory. Proud passes that path to its GitHub API SDK, which resolves the repository from Git remote `origin` and uses the live checkout for local source and branch comparison.

The launcher preserves `PROUD_GITHUB_TOKEN` or `GITHUB_TOKEN`. Without one, Proud tries `git credential fill`, so an existing OS keychain or Git credential helper can authenticate requests. If no reusable credential is available or it fails validation, the centered credential modal accepts hidden token input and saves the successful token with owner-only permissions. It also respects `PROUD_GITHUB_TOKEN_FILE`, `PROUD_GITHUB_REPOSITORY`, and `PROUD_GITHUB_API_URL`.

## Startup Modes

| Variable | Values | Result |
| --- | --- | --- |
| `PROUD_START` | `prs`, `overview`, `diff`, `compare`, `demo`, `help`, `none` | Initial Proud surface |
| `PROUD_PR_QUERY` | GitHub search text | Initial pull request query |
| `PROUD_PR_NUMBER` | Pull request number | Required by `overview` and `diff` |
| `PROUD_COMPARE_BASE` | Ref | Compare base |
| `PROUD_COMPARE_HEAD` | Ref | Compare head |
| `PROUD_GITHUB_REPOSITORY` | `owner/repo` | Override Git remote repository discovery |
| `PROUD_GITHUB_API_URL` | API base URL | Use GitHub Enterprise or a test API |
| `PROUD_GITHUB_TOKEN_FILE` | File path | Override Proud's reusable token storage path |

Arguments after the script name are forwarded to the isolated Neovim binary.
