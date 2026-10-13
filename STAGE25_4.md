# Stage 25.4 — Text/layout integration

Development baseline remains 0.2.0; no release/version bump is performed here.

## Scope

Pure, allocation-free helpers connecting one-line text measurement to the
existing vertical `layout.Stack`. No second layout system, no alignment policy
(stage 26), no widgets (stage 25.5).

## Added

- `src/text.zig` imports `layout.zig` (one-way; layout stays independent):
  - `LineBox { width, height, glyph_count }`.
  - `lineHeight(font, scale)`: `(ascent - descent + line_gap) * scale` with
    explicit `InvalidFont` (non-finite/negative metrics, non-positive raw
    height) and `InvalidScale` (bad/overflowing scale) errors.
  - `lineBox(font, utf8, scale)`: width via `measure` + height via
    `lineHeight`; error priority is height first, then text errors.
  - `baselineInRect(rect, font, scale)`: `[rect.x, rect.y + ascent * scale]`.
    Horizontal padding is already baked into `rect.x` by `layout.next`;
    bad rects and `rect.y + rise` overflow return `InvalidPosition`.
- 5 new `text` tests + 1 new `root` Context test (105 total):
  - Line height values, invalid fonts/scales.
  - Line box width/height/count, empty, fallback, UTF-8/scale errors.
  - Baseline offsets at scale 1/2, bad rects, overflow (`3.3e38 + 8e37`).
  - Two-row layout with spacing 5/3: rows at y 20/34, baselines 28/42,
    quads at (16,21) and (16,35), one batched command.
  - Overflow policy: 70px text in 20px row still emits; clip stays on the
    command (GPU scissor), layout cursor is unaffected.
  - Context flow: `lineBox` sizes `nextLayoutRect`, `baselineInRect` feeds
    `drawTextBaseline` across two rows, view verified.

## Contracts

- Row height must come from `lineHeight`/`lineBox`; baseline from
  `baselineInRect`. Glyphs for the sample metrics land strictly inside the
  line box (top `rect.y + 1`, bottom `rect.y + 9` in an 11px row).
- Layout never clips; rendering clips via command `ClipRect`. Width overflow
  is legal and visible only through the clip.
- All helpers are pure and allocation-free; failures touch no geometry.

## Validation

- `zig fmt --check build.zig src bench examples`: pass.
- `zig build test --summary all`: 105/105 pass (Debug).
- `zig build test -Doptimize=ReleaseFast --summary all`: 105/105 pass.
- `zig build integration` and `-Doptimize=ReleaseFast`: exit 0.
- `zig build bench -Doptimize=ReleaseFast`: exit 0.

## Risks / pending

- No horizontal alignment, wrapping, or multiline; single baseline run only.
- No `label()` widget yet (25.5); callers still wire layout + baseline manually.
- No text-specific benchmark yet (25.6).
