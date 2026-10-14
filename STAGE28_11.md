# Stage 28.11 — Ordered text input bridge

- Added `src/text_input.zig`, exported as `nitro_ui.text_input`.
- Consumes ordered caller-owned `input.Event` slices and applies UTF-8 scalar insertion, Backspace, Delete, Left/Right, Home/End and Shift selection to `text_edit.Buffer`.
- Honors focus-loss events; accepts initial Shift and focus state explicitly. Logical navigation key codes are translated by the engine.
- No heap allocations or platform dependencies. Single-line editor only; no IME, grapheme segmentation, clipboard, undo, or visual widget.
- `input.Processor.events` retains only the latest batch: callers must pass a complete ordered stream or invoke this bridge once per batch, carrying modifier/focus state across batches.
- Failure is atomic for the failing insertion, **not** for an entire batch; preceding successful events remain applied. The caller must not replay partially applied batches.
- Three unit tests added but **not run**: Zig 0.17.0 compiler unavailable in this environment.
- Complexity: UTF-8 validation and byte shifting O(n) per edit, no dynamic allocation.
- Version remains 0.2.0. No GitHub publication.
