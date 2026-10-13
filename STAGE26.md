# Stage 26 — Layout expansion (horizontal, alignment, cross-axis sizing)

Development baseline remains 0.2.0; no release/version bump is performed here.

## Scope

Extend the existing vertical-only `layout.Stack` to support horizontal flow,
cross-axis alignment, and explicit cross-axis sizing — without breaking any
existing vertical call sites.

## Added

- `layout.Direction = enum { Vertical, Horizontal }`
- `layout.Alignment = enum { Start, Center, End }`
- `Stack.pushDirection(bounds, spacing, direction, alignment)` — new explicit
  push; `push(bounds, spacing)` remains and defaults to `Vertical, Start`.
- `Stack.next(size_cross, size_main)` — unified for both directions:
  - Vertical: `size_main` = height, `size_cross` = width (null → available
    inner width minus 2×spacing.x).
  - Horizontal: `size_main` = width, `size_cross` = height (null → available
    inner height minus 2×spacing.y).
  - Cross-axis position respects `Alignment` when `size_cross` < available.
- `crossAlignOffset` helper for Start/Center/End math.
- 9 new `layout` tests (114 total):
  - Horizontal flow: cursor_x advances, items placed left-to-right.
  - Horizontal alignment: Center/End/Start with explicit cross size.
  - Vertical alignment: Center/End/Start with explicit cross size.
  - Horizontal with explicit cross size and spacing.
  - Nested horizontal inside vertical (and vice versa).
  - Horizontal overflow: cursor advances past bounds; layout doesn't clip.
  - `pushDirection` validates rect/spacing.

## Contracts

- Backward compatible: `push`/`next` unchanged for vertical callers.
- Layout never clips; rendering clips via command `ClipRect`.
- Cross-axis alignment only applies when explicit `size_cross` < available.
- No allocations; O(1) per `next`.

## Validation

- `zig fmt --check build.zig src bench examples`: pass.
- `zig build test --summary all`: 114/114 pass (Debug).
- `zig build test -Doptimize=ReleaseFast --summary all`: 114/114 pass.
- `zig build integration` and `-Doptimize=ReleaseFast`: exit 0.
- `zig build bench -Doptimize=ReleaseFast`: exit 0, 23 cases unchanged.

## Risks / pending

- No `wrap`/`flex`/`grid` — single-axis sequential only.
- No per-item alignment override (region-level only).
- No horizontal benchmark separate from widget paths.