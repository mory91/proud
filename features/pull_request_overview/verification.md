# Verification

Run:

```sh
nvim --headless -u tests/minimal_init.lua -l tests/run_unit.lua
nvim --headless -u tests/minimal_init.lua -l tests/run_e2e.lua
nvim --headless -u tests/minimal_init.lua -l bench/run.lua
```

The overview must render before provider and credential-validation callbacks, preserve checked output in unit tests, exercise view-state changes and `<CR>` diff navigation through E2E input, hydrate a deliberately delayed provider response without reopening the scene, preserve the tree-state identity used by keyboard callbacks, and pass literal `j`, `<Space>`, `l`, and `h` navigation across the loading and hydrated tree. It must reject multiline commit text as buffer content, ignore late results after scene closure, and meet the fixed-workload SLA.

The overview unit contract verifies two columns of horizontal padding on both sides of every detail line and keeps card outer edges inside those margins at multiple widths. Long titles, metadata, descriptions, Markdown headings, and unbreakable tokens are pre-wrapped and fitted so every physical buffer line preserves those margins with native window wrapping enabled or disabled. It also verifies native rounded conversation cards, muted-grey spans for the full `Description` and `Conversation` separator rows, and `name · relative age · reviewed/change requested/commented` in each card's header. GitHub `in_reply_to_id` links survive provider normalization and render narrower indented reply cards beneath their parent. The real-terminal contract checks the same padding geometry, semantic colors for file statuses, commit IDs, checks, PR details, review states, separators, card metadata, and action hints via `tests/terminal/run.sh`. A source-backed metadata case renders unique API reviewer decisions, requested reviewers, labels, body text, issue comments, and a linked reply in a real Neovim terminal, rejects fixture-only reviewer or conversation strings, and scrolls cards through partial visibility and complete viewport exit. A delayed hydration case proves the overview is visible first and remains valid after multiline API commit data arrives. Native-card geometry, partial clipping, scrolling, resizing, and cleanup are independently verified by `features/conversation_cards/tests`.
The lifecycle E2E repeatedly opens and closes this screen through real terminal input, verifies retained heap growth/trend within `64 KiB`, and rejects retained buffers or windows.
