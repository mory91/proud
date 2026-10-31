# Full-File Diff With Threads

Read the complete file with deleted rows inserted and additions colored inline, then act on review threads without leaving the current line. The three-pane diff opens immediately with loading content while pull metadata, patch data, and review threads hydrate independently. Full-file content is loaded lazily for the selected file so large pull requests do not materialize every source file at once. Reviewers can move through the file tree and press `<CR>` on a row to load that file, then navigate threads, reply, resolve, and keep drafts while preserving the author, timestamp, and body of each conversation.

## Related Code

- `feature.lua` overlays patch rows onto full-file source and combines them with thread conversations and review actions.
- `tests/unit_spec.lua` verifies full-file reconstruction, inline diff colors, replies, resolution, and thread navigation.
- `tests/e2e_spec.lua` verifies keyboard-driven full-file navigation, thread resolution, and independent delayed PR/patch/thread hydration in Neovim.
- `bench/benchmark.lua` covers 1,200 full-file lines and 1,000 threads with three comments each.
- `tests/memory_leak_spec.lua` verifies repeated real-screen open/close lifecycle remains within the feature's memory and resource SLA.
