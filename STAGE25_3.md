# Stage 25.3 — Unicode, metrics and fallback

Development baseline remains 0.2.0; no release/version bump is performed here.

## Scope

Hardening of stage 25.2 contracts without new public APIs or layout changes.
No complex shaping. Newline/multiline policy still deferred: control bytes
(including `\n`) resolve like any other codepoint.

## Added

- `src/text.zig`: 8 new tests (12 total in file):
  - UTF-8 scalar boundaries (U+0000..U+10FFFF, D7FF/E000 valid) and lengths.
  - Rejection of empty, standalone continuations, illegal leads (C1/FE/FF/F5),
    truncated sequences, bad continuations, overlong 3/4-byte, DFFF surrogate.
  - Measure edges: empty string (0/0), invalid scales (0/neg/inf/nan),
    missing glyph without fallback, fallback resolution, 256-glyph long string,
    scale overflow via huge advance, invalid UTF-8 passthrough.
  - Zero-area glyph skip: mixed zero/normal "AB" yields 2-count metrics but
    one quad (4v/6i/1c).
  - Non-finite baseline (inf/nan) and inf bearing rejected as InvalidPosition
    with zero geometry drift; buffer remains reusable.
  - Merged-command rollback: rect + "AA" overflowing restores 4v/6i/1c and the
    exact prior command; single-glyph retry then merges to 8v/12i.
  - Command-capacity exhaustion with mismatched texture leaves prior command
    untouched.
  - Long-string batching: 256x "A" emits 1024v/1536i/1c with all indices
    in bounds.
- `src/root.zig`: 1 new test for `Context.drawTextBaseline`:
  - Idle call rejected, missing geometry reported, MissingGlyph/InvalidUtf8
    leave geometry counts unchanged while staying in `building`, retry merges,
    ready-state call rejected, view verified after `endFrame()`.

## Contracts confirmed

- Empty input measures 0 advance / 0 glyphs; emission writes nothing.
- `scale <= 0`, non-finite, or overflowed accumulation returns InvalidScale
  before touching geometry.
- Missing codepoint without fallback returns MissingGlyph before touching
  geometry; with fallback the fallback advance/geometry is used.
- Non-finite baseline or derived quad coordinates return InvalidPosition with
  full logical rollback (counts + merged command).
- Capacity failures (vertex/index/command) are logically atomic and restore a
  previously merged command.

## Validation

- `zig fmt --check build.zig src bench examples`: pass.
- `zig build test --summary all`: 99/99 pass (Debug).
- `zig build test -Doptimize=ReleaseFast --summary all`: 99/99 pass.
- `zig build integration` and `-Doptimize=ReleaseFast`: exit 0.
- `zig build bench -Doptimize=ReleaseFast`: exit 0, 12 cases unchanged.

## Risks / pending

- Fonts are still caller-validated; unvalidated metrics (inf bearing/advance)
  are rejected per-call but not cached.
- No horizontal layout, label widget, or text benchmark yet (stages 25.4-25.6).
- No real-engine or async-GPU validation; headless sync consumption only.
