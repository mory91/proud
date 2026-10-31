# Proud

Proud is a fast, memory-conscious pull request reviewer for Neovim. It keeps review work in familiar buffers, uses GitHub through an asynchronous Lua REST SDK, compares local branches offline through Git, and enforces performance SLAs as part of every verification run.

The visual direction is defined in `proud.html`. The supplied `design.html` remains the original bundled design reference.

## Install

```lua
{
  "mory91/proud",
  dependencies = {},
  config = function()
    require("proud").setup({
      provider = {
        kind = "github",
        repository = "owner/repository",
        query_debounce_ms = 250,
        description_debounce_ms = 80,
      },
      ui = {
        theme = "proud-dark",
        themes = {
          ocean = {
            extends = "proud-dark",
            groups = {
              ProudAccent = { fg = "#FFFFFF", bg = "#006469", bold = true },
              ProudAccentText = { fg = "#15B7B7" },
            },
          },
        },
        windows = {
          margin = { top = 3, bottom = 2, left = 2, right = 2 },
          gap = 3,
        },
      },
      keymaps = {
        next_tab = { "<Tab>" },
        previous_tab = { "<S-Tab>" },
      },
    })
  end,
}
```

The `ui.windows` values control the outer spacing of Proud's rounded floating-window pair. `gap` is the empty space between the list and preview windows; top and bottom margins keep borders clear of tablines, statuslines, and command areas on every terminal size. Rounded surfaces and native split workspaces react to terminal resizing through `VimResized`, recomputing pane widths and heights, in-window headers and separators, outside selectors, and rendered content widths without reopening the scene. The verified `ui_resize` feature owns those relayout calculations, preserves source rows for semantic diff content, and keeps rendered straight rows where the terminal contract requires them. Above the pair, the source selector exposes `Review requested`, `Mine`, `All open`, `Recently viewed`, and `Branches`, with `All open` selected by default. Its buttons use the default one-row borderless solid-fill style: purple with white text when active, grey when inactive. Their next/previous actions are remappable and change the active PR query without displaying key hints. The PR browser uses native top header sections instead of floating-window titles: `PRs > ...` is an in-page filter prompt with a right-aligned `filtered/total` count, and `Preview` is a muted grey label. Filter edits are applied locally immediately and sent to GitHub only after `provider.query_debounce_ms` settles. Cursor-selected PR descriptions wait for `provider.description_debounce_ms`, so held movement fetches the settled selection instead of every intermediate PR. Proud reads the active `showtabline`, `laststatus`, and `cmdheight` settings and does not overwrite user display configuration.

The shared UI theme registry is available through `require("proud.ui").themes`. It supports named themes, inheritance, registration, lookup, selection, and Neovim highlight application. Proud ships `proud-dark`, `proud-light`, `proud-midnight`, `proud-ocean`, `proud-forest`, `proud-sunset`, and `proud-paper`; `ui.theme` selects one, while `ui.themes` adds custom themes. A custom theme may provide the complete highlight set or extend any preset and override only the groups it changes. See `docs/UITHEMES.md` for the framework API and preset reference.

The shared UI text API is available through `require("proud.ui").wrap_text` and `require("proud.ui").content_lines`. By default both follow Neovim's global `wrap` setting, preserving explicit line breaks, splitting unbreakable tokens safely, and respecting display-cell width for Unicode. `content_lines` additionally enforces configurable left/right padding: wrapped rows fit the content box, while non-wrapped rows retain the complete line for native horizontal navigation. Explicit `{ wrap = true }` or `{ wrap = false }` overrides the Neovim default. See `docs/UICONTENT.md`.

Neovim 0.11 or newer, `curl`, and Git are required. GitHub requests use `lua/proud/github.lua`; the provider never invokes a GitHub command-line client. Branch compare requires a local Git repository.

## Authentication

Before the first live GitHub scene, Proud resolves credentials in this order:

1. `provider.token` passed to `setup()`.
2. `PROUD_GITHUB_TOKEN`, `GITHUB_TOKEN`.
3. `provider.token_file`, `PROUD_GITHUB_TOKEN_FILE`, or Proud's saved token.
4. The password returned by `git credential fill`, including OS keychain and configured Git credential helpers.

If none is available or validation fails, Proud opens a centered credential modal. Token entry is hidden, validation is performed against the configured repository, and a successful token is saved with owner-only permissions under Neovim's state directory. Later scenes and later Neovim launches reuse it without asking again. Rejected tokens are never persisted or shown in the error.

For a manually managed token:

```sh
export GITHUB_TOKEN=github_pat_your_token
```

Alternatively, configure a Git credential helper and leave token resolution to step 4. Set `provider.base_url` for GitHub Enterprise and `provider.repository` when Git remote `origin` is unavailable.

## Commands

```vim
:Proud prs
:Proud open 482
:Proud diff 482
:Proud compare main feat/monitor-diffs
:Proud help
:Proud demo
:Proud demo review
```

## Feature Ownership

Every feature is self-contained in `features/<feature>/` with:

- `description.md` defining the user-facing contract.
- `feature.lua` containing the related implementation.
- `tests/unit_spec.lua` and `tests/e2e_spec.lua`.
- `bench/benchmark.lua` with a fixed workload.
- `SLA.md` stating hard timing and memory limits.
- `verification.md` recording the verification workflow.

| Feature | Primary responsibility |
| --- | --- |
| `github_api` | GitHub REST client, pagination, auth, enrichment, and diff retrieval |
| `github_credentials` | Centered credential modal, validation, secure persistence, and reuse |
| `pull_request_browser` | Query, preview, and open pull requests |
| `pull_request_overview` | Description, files, commits, checks, and conversation |
| `single_diff_threads` | Full-file inline diff, replies, drafts, and resolution |
| `review_submission` | Comment, approve, and request-changes review submission |
| `branch_compare` | Offline two-dot and three-dot Git comparison |
| `keymap_help` | Remappable key and command reference |

## Verification

```sh
make verify
```

This runs:

1. Isolated GitHub API SDK unit and Neovim E2E tests.
2. Unit tests for model behavior and boundary cases.
3. Headless and real-terminal Neovim E2E tests for buffers, mappings, and user flows.
4. Warm, fixed-workload timing and Lua heap benchmarks.
5. A basic design artifact integrity check.

Any failed assertion or breached SLA exits non-zero. Benchmarks use warmups, p50/p95 reporting, deterministic fixtures, and result checksums; fixture construction is excluded from timed regions.

## Isolated Test Environment

```sh
./scripts/setup_proud_test_env.sh
PROUD_GIT_REPO=/path/to/live/checkout ./scripts/run_proud_test_nvim.sh
```

This runs the latest working-tree plugin with a separate `test-env/nvim/bin/nvim` binary and runtime. Neovim configuration and state are isolated under `test-env/state/`, so the normal local Neovim build and setup are not modified. See `docs/TEST_ENV.md`.

## Performance SLAs

| Feature | Fixed workload | p95 | Heap delta |
| --- | ---: | ---: | ---: |
| GitHub API SDK | 2,000 file payloads | 4 ms | 768 KiB |
| GitHub credentials | 100 validation errors | 2 ms | 256 KiB |
| Pull request browser open | 25 visible PRs from 500 + selected description | 2 ms | 256 KiB |
| Pull request browser prefetch | 2 sequential pages × 25 PRs | 2 ms | 256 KiB |
| Pull request browser render | 100 retained PRs + 100 description lines | 3 ms | 512 KiB |
| Pull request filter debounce | 200 rapid edits | 2 ms | 256 KiB |
| Pull request description debounce | 200 rapid selections | 2 ms | 256 KiB |
| Pull request source debounce | 200 rapid source changes | 2 ms | 256 KiB |
| Sidebar movement | 500 expanded nodes via attached `j`/`k` handler | 0.5 ms | 64 KiB |
| Pull request overview | 200 files + 250 body lines | 4 ms | 768 KiB |
| Single diff and threads | 1,200-file lines + 1,000 threads | 8 ms | 2 MiB |
| Branch compare | 100 commits + 500 files | 3 ms | 512 KiB |
| Keymap help | 80 mappings | 1 ms | 128 KiB |

The hard limits are enforced by `bench/run.lua`. Raising an SLA requires a product-level justification and a corresponding feature `SLA.md` update; a benchmark may not be weakened merely to make a regression pass.
