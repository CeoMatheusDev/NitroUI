# Stage 26.0 — Horizontal layout (unvalidated)

## Changes
- `src/layout.zig`: `Direction`, `Stack.pushHorizontal`, direction-aware `Stack.next`; existing `push` remains vertical. Explicit widths required in horizontal regions; horizontal spacing uses `Spacing.x` and top inset uses `Spacing.y`. Nested regions remain independent.
- `src/root.zig`: `Context.pushHorizontalLayout` restricted to building frames.
- Three regression tests added for positioning, overflow/atomicity and invalid frame state.

## Contracts
- No allocator, GPU or OS integration added. No changes to existing `pushLayout`, `nextLayoutRect`, `label`, vertex/index/command representations.
- Horizontal placement does not clip to bounds (same policy as vertical). Width `null` in horizontal mode returns `InvalidSize` without consuming layout state.
- `pushHorizontalLayout` is additive API.

## Validation
- Source reviewed; Zig 0.17.0 is not installed in this environment. Formatting, compilation, tests, and benchmarks are **not executed**. Run `zig fmt build.zig src bench examples`, `zig build test`, `zig build test -Doptimize=ReleaseFast`, `zig build integration`, and `zig build bench -Doptimize=ReleaseFast` before accepting.
- This work is not published to GitHub. Version remains 0.2.0.
