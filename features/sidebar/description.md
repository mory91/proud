# Composable Sidebar

Proud's sidebar is a reusable collapsible tree rendered in a native Vim pane. It is composed from two shared primitives: section rows and tree nodes. A row contains one to five sections, and each node group defines the spacing between those sections. Every composed row is normalized to one buffer line, including API commit subjects with multiline bodies. Sections may contain multiple semantic spans, allowing a single changes section to render additions green and deletions red.

Tree nodes may be headers, paths, leaves, or future nested records. Headers remain expandable while their asynchronous children are still loading, and tree layout snapshots preserve the selected node and every explicit expansion choice when data replaces placeholder state. Headers use a shared `Label metadata` pattern such as `Files 5 · 1 of 5 viewed`, `Commits 6`, or `Checks 4 of 5 passing`. Labels are white and metadata is grey. Header children appear only while expanded. Entries are navigated vertically, while branches can be opened, closed, or toggled through configurable keymaps. Directional tree keys and simple open/close aliases are both supported. File leaves use the group spacing `name  +43-110  ◆2  viewed`; commit leaves use hash and message with a different spacing profile. Expanded checks use a fixed-column `✓ lint                 18s` layout, with semantic pass/fail symbols, bright names, and muted durations. The pull request overview composes commits, checks, and a directory/file hierarchy from these components in its left Vim pane.

Selection movement is cursor-only: `j` and `k` update the selected tree node and native window cursor without repainting the sidebar or any host panes. Hosts receive only a lightweight `on_change("selection")` notification when selection changes. Expansion, collapse, and viewed-state changes remain structural and may request a full refresh. This distinction keeps rapid traversal responsive even when the host composes expensive overview panes and conversation cards.

## Related Code

- `lua/proud/components/section_row.lua` owns up-to-five-section rows and group-specific spacing.
- `lua/proud/components/tree.lua` owns expandable nodes, visible-row navigation, contextual activation, and tree rendering.
- `feature.lua` composes overview status headers, directory/file nodes, commit nodes, and check nodes.
- `tests/unit_spec.lua` verifies section limits, spacing, hierarchy, statuses, and semantic row composition.
- `tests/e2e_spec.lua` opens the component in a real Neovim workspace and drives expansion, viewed state, and activation.
- `tests/memory_leak_spec.lua` verifies repeated overview/sidebar screen lifecycles remain bounded.
- `bench/benchmark.lua` measures rendering and the attached movement handler for 500 expanded nodes under explicit timing and heap SLAs.
