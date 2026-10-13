# Stage 25.6 — Text benchmark

Development baseline remains 0.2.0; no release/version bump is performed here.

## Scope

Headless, deterministic text workloads in `bench/headless.zig` only. No
library hot-path changes, so no before/after improvement is claimed.

## Added

- Shared engine-owned bench font (glyphs 63/?, 65/A, U+00E9, U+20AC,
  U+1F600; texture 9; fallback 63), validated once in `main`.
- `text` × 4 sizes: layout + one ASCII label per row (1-byte decode, lookup
  hit, measure, UV emission); same geometry/verification as rect/widget
  (count*4v/count*6i/1 command) for direct per-widget comparison.
- `textuni` × 4 sizes: same label path cycling A/é/€/😀/Z (1/2/3/4-byte hits
  plus a fallback miss every 5th row); identical output shape.
- `textlong` × 3 lens (64/256/1024 chars): one long ASCII label per frame
  through a single layout row; reports `ns_char_med` alongside frame stats
  and verifies glyph-count scaling + single-command batching.

## Results (ReleaseFast, Fedora, this machine — reproducible, not portable)

- Per-widget medians at 4096: rect ~13ns, widget ~30ns, idstr ~32ns,
  text ~37ns, textuni ~41ns. Text−widget delta (~+7ns) reflects
  decode+lookup+measure+UV vs interaction; textuni−text (~+4ns) reflects
  multibyte/fallback mix. Machine-specific; compare only within one run.
- Per-char medians (textlong): ~21-23ns/char, below per-widget label cost
  because one `label` call amortizes layout/measure over many glyphs.
- All 23 cases verify exact vertex/index/command counts and the
  one-command batching contract over 300 measured frames (30 warm-up).

## Validation

- `zig fmt --check build.zig src bench examples`: pass.
- `zig build test --summary all`: 107/107 pass (Debug).
- `zig build test -Doptimize=ReleaseFast --summary all`: 107/107 pass.
- `zig build integration` and `-Doptimize=ReleaseFast`: exit 0.
- `zig build bench -Doptimize=ReleaseFast`: exit 0, 23 cases.

## Risks / pending

- End-to-end per-frame timing only; no isolated decode/lookup micro-timings.
- No rasterization, real engine, or async-GPU coverage (stages 29-30).
