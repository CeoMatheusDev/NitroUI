# Stage 25.5 — Widget `label()`

Development baseline remains 0.2.0; no release/version bump is performed here.

## Scope

Lightweight non-interactive text widget reusing font, layout, and draw
contracts. No shaping, wrapping, alignment, or style text color (deferred).

## Added

- `Context.label(rect, font, utf8, scale, color, clip)` in `src/root.zig`:
  - Caller sizes `rect` (canonically via `text.lineBox` + `nextLayoutRect`).
  - Baseline derived via `text.baselineInRect`; emission via
    `drawTextBaseline` (`text.emitBaseline` + `addTexturedQuad` batching).
  - Widget-level checkpoint/rollback (geometry + interaction + merged
    command), idempotent over the emission-level rollback.
  - No ID, no `interact()`: consumes no duplicate-tracking capacity and
    leaves `interaction_state` untouched. Returns `text.Metrics`.
  - Explicit `scale`/`color`/`clip`; engine owns font storage and texture.
- Param rename (call-compatible, positional): `Context.widgetId(label)` and
  `Context.pushId(label)` params renamed to `name`; required because Zig
  0.17 rejects a parameter shadowing the new sibling `label` declaration.
  `ids.Stack` untouched.
- 2 new `root` tests (107 total):
  - Layout rows + Unicode (`"AB"`, `"Aé"`, empty): metrics, batching into one
    command, zero `visited_count`, empty writes nothing.
  - Failures atomic: idle-state, `MissingGlyph`, `InvalidScale`,
    `InvalidUtf8` leave counts at zero; `OutOfCapacity` on `"AA"` restores
    4v/6i/1c plus the exact prior command and interaction snapshot; later
    `interact` still tracked normally.

## Contracts

- Unicode per stages 25.2-25.3; overflow follows 25.4 (layout never clips,
  clip lives on the command).
- Zero allocations (no `Allocator` parameter; borrowed engine buffers only).

## Validation

- `zig fmt --check build.zig src bench examples`: pass.
- `zig build test --summary all`: 107/107 pass (Debug).
- `zig build test -Doptimize=ReleaseFast --summary all`: 107/107 pass.
- `zig build integration` and `-Doptimize=ReleaseFast`: exit 0.
- `zig build bench -Doptimize=ReleaseFast`: exit 0.

## Risks / pending

- No `labelClipped` clip-stack variant; explicit clip only (matches
  button/checkbox/slider).
- No style text color; color is an explicit argument.
- No text benchmark yet (25.6).
