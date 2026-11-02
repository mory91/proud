# Diff Pane

The pane that shows a diff, one changed file at a time, inside a window owned by a host page (the compare page). It has no tab or scene of its own.

Two sources:

- **Working tree** ("All changes" on the compare page): each file opens as the **real file** in a normal, editable buffer, with Neovim's own line numbers, sign column, syntax and LSP. It is compared live with a base revision (the merge base) using Neovim's built-in diff engine: added and changed lines get a green background and a `+` sign, and deleted lines appear as virtual lines on a red background at their old position. The diff colors are backgrounds only, so code keeps its syntax colors; deleted lines are colored with the base text's treesitter highlights (parsed in the background, colored as they scroll into view), or drawn plain when the language has no parser. Editing updates the diff as you type, and saving writes the file. Review threads show as `◆` (open) or `◇` (resolved) signs with an end-of-line preview of the first comment; they are extmarks, so they move with the text.
- **Commit**: one commit's version of the file in a read-only snapshot buffer (with the file's syntax), compared with the same file in the commit's parent, so it shows the change of that commit. Threads are not placed on commits.

A deleted file is shown as its old text with every row marked deleted. A window bar shows the host's label (`base...head`, or the commit), the file path, live `[+added −deleted]` counts and the file's position (`1 / 5`). While loading, on a git error (shown as git reports it), or with nothing to show, the pane shows a status buffer instead.

`]f` / `[f` switch files and `]t` / `[t` jump to threads. `K` on a line with a thread opens the **thread window**: a rounded float anchored beside the line (below it, or above when there is more room) with every comment in full, wrapped, replies indented under the first comment, and all threads on that line. It opens without taking focus; `K` again focuses it to scroll, and `q` / `<Esc>` close it and return to the diff. Moving off the line, entering Insert mode, switching files or closing the page closes it, and `]t` / `[t` move an open window to the next thread. On a line without a thread `K` falls through to LSP hover (or Neovim's `K`). The host can add its own actions the host can add its own actions (the compare page adds the sidebar toggle). No `r`, `R` or `q` mappings are placed on real files (in Neovim those are replace, Replace mode and macro recording). When the host closes, the pane removes every decoration and mapping from your files, deletes commit snapshots, and unloads the files it opened, except those with unsaved edits or shown elsewhere.

## Related Code

- `feature.lua` shows files from either source, attaches `ui.inline_diff`, places thread signs and previews, and cleans up for its host.
- `lua/proud/ui/inline_diff.lua` draws a live diff on any buffer with `vim.diff`.
- `lua/proud/git.lua` runs git asynchronously (changed files with line counts, file contents at a revision, commit parents, background PR checkout).
- `lua/proud/fixture_repo.lua` builds a real fixture repository (one commit per changed file, with a local origin) for the demo, tests and benchmarks.
- `tests/unit_spec.lua` verifies the window bar, status and error views, thread previews, thread data, and inline diff decorations.
- `tests/e2e_spec.lua` verifies real editable files, live re-diffing on edit, thread signs that follow edits, file and thread navigation, host actions on files, commit snapshots against their parent, cleanup, and shared background checkout jobs.
