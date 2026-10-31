# Keymap Help

Expose every action binding and command in a compact Help surface. Normal review scenes stay focused on content and never print keyboard legends. Mappings are data-driven and remappable through `setup({ keymaps = { ... } })`; Help always reflects the resolved configuration and can be toggled without disturbing review buffers.

## Related Code

- `feature.lua` renders the resolved action registry and controls the Help workspace.
- `lua/proud/keymap.lua` owns defaults, overrides, labels, and buffer/workspace binding helpers.
- `tests/unit_spec.lua` verifies key and command documentation.
- `tests/e2e_spec.lua` verifies opening and closing the help surface.
- `bench/benchmark.lua` covers 80 mappings in 20 groups.
- `tests/memory_leak_spec.lua` verifies repeated real-screen open/close lifecycle remains within the feature's memory and resource SLA.
