# Proud Test Environment

`test-env/nvim/` contains an isolated Neovim binary and runtime copied from the configured source installation. It does not use the user's Neovim config, data, state, cache, or plugin directories.

Generated runtime and state are ignored by Git. Rebuild them with:

```sh
./scripts/setup_proud_test_env.sh
```

Run Proud against a live Git checkout with:

```sh
PROUD_GIT_REPO=/path/to/checkout ./scripts/run_proud_test_nvim.sh
```

The launcher:

- resolves the checkout's Git top level;
- changes Neovim's working directory to that repository so the GitHub API SDK resolves its remote;
- preserves GitHub token environment variables while isolating Neovim's XDG directories;
- sets isolated XDG directories below `test-env/state/`;
- loads the plugin directly from this working tree;
- starts `Proud prs` by default;
- forwards additional arguments to the isolated Neovim binary.

Examples:

```sh
PROUD_GIT_REPO=/path/to/checkout PROUD_START=demo ./scripts/run_proud_test_nvim.sh
PROUD_GIT_REPO=/path/to/checkout PROUD_START=diff PROUD_PR_NUMBER=482 ./scripts/run_proud_test_nvim.sh
PROUD_GIT_REPO=/path/to/checkout PROUD_START=none ./scripts/run_proud_test_nvim.sh --clean
```

Authentication comes from `PROUD_GITHUB_TOKEN`, `GITHUB_TOKEN`, `PROUD_GITHUB_TOKEN_FILE`, or `git credential fill`. If none is usable, Proud opens its centered credential modal and reuses the validated token later. Set `PROUD_GITHUB_REPOSITORY=owner/repo` when the checkout has no `origin` remote and `PROUD_GITHUB_API_URL` for GitHub Enterprise.
