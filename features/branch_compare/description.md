# Compare

The page for every diff: a sidebar next to the diff pane (`features/diff_view`). `:Proud compare <base> <head>` compares two branches; a pull request's diff (`:Proud diff <n>`, or `<CR>`/`d` on a file in the overview) is this page for its `base...head`, with the PR's review threads.

The head is **checked out in place** in the current repository: a local branch, or `origin/<head>` as a local tracking branch; for a pull request, the overview has usually done this already in the background. If git fails (uncommitted changes in the way, a missing branch), the diff pane shows git's own message.

The sidebar, like the design, has three sections:

- **Compare**: the mode (three-dot from the merge base, or two-dot from the base tip), `base @ <commit>`, `head @ <commit>`, `↑ahead ↓behind`, and the PR number or `no PR yet`.
- **Commits**: `All changes` first, then the branch's commits, newest first; the shown one is marked `●`. `<CR>` on `All changes` shows every change from the base in the real, editable files (local edits included). `<CR>` on a commit shows **that commit's change**: each file it touched, against the commit's parent, read-only.
- **Files**: the files of the current selection, with status, `+added −deleted` and open thread counts. `<CR>` (or `d`) opens a file in the diff pane and moves focus there to edit.

`]f` / `[f` in the diff pane move the sidebar's file selection along. `<leader>e` hides or shows the sidebar, from either pane; the page stays open and the sidebar keeps its state. In a plain compare, `S` swaps base and head (checking out the new head); `<C-d>` toggles two-dot and three-dot. `q` in the sidebar closes the page. The page appears at once with placeholders and fills in when git finishes.

## Related Code

- `feature.lua` checks out the head, gathers the comparison through `lua/proud/git.lua`, builds the sidebar tree, and drives the diff pane.
- `features/sidebar/feature.lua` provides the tree, its keys, and activation of commits.
- `lua/proud/ui/workspace.lua` hides and shows panes (`ui.toggle_pane`).
- `tests/unit_spec.lua` verifies the sidebar sections, commit selection markers, totals, thread counts, swapping, modes, and pull request metadata.
- `tests/e2e_spec.lua` drives a real fixture repository: checkout in place, file and commit selection, sidebar sync, the sidebar toggle, swapping, git errors, delayed PR metadata, the overview's background checkout, and opening at a commit.
- `bench/benchmark.lua` covers rendering and rebuilding the sidebar for 100 commits and 500 files.
- `tests/memory_leak_spec.lua` verifies repeated real-screen open/close lifecycle remains within the feature's memory and resource SLA.
