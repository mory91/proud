# Conversation Cards

Render overview conversation entries as reusable native Neovim rounded floating windows. Each card is a real window rectangle with a rounded border; card content never contains ASCII or Unicode border glyphs. Root cards inherit the overview background exactly, while replies use the subtle panel shade to communicate nesting without adding another prominent surface. The overview passes its horizontal inner padding to the layout so cards begin after the left margin and stop before the right margin. Card headers combine author, review or comment metadata, and relative age with semantic colors before the body message. Body text uses the shared `ui.wrap_text` capability to remain inside the card's content box. Replies are narrower and indented beneath their parent. Cards stay mounted while any part intersects the host viewport: visible rows are cropped into the native window, while a top or bottom rounded edge is omitted only when that edge is outside the viewport. A card and its native window are removed after it completely exits. The component follows buffer scrolling and terminal resizing and owns complete buffer/window cleanup.

## Related Code

- `feature.lua` implements responsive card layout, native-window synchronization, highlighting, and lifecycle cleanup.
- `tests/unit_spec.lua` verifies geometry, partial top/bottom clipping, cropped content, native border edges, metadata colors, scrolling, resizing, and cleanup.
- `tests/e2e_spec.lua` opens real Neovim windows through the overview and verifies native card and full-exit behavior.
- `tests/memory_leak_spec.lua` verifies repeated native-window lifecycle stability.
- `bench/benchmark.lua` enforces layout timing and memory SLAs for 100 cards.
