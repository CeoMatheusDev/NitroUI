# Stage 25.2 — UTF-8 and text geometry

Development baseline remains 0.2.0; no release/version bump is performed here.

## Added

- `src/text.zig`: strict allocation-free UTF-8 scalar decoder, one-line text measurement, and baseline-oriented glyph emission.
- `draw.Buffer.addTexturedQuad`: explicit position/UV quad primitive used by text without changing `Vertex` or `Command` layout.
- `Context.drawTextBaseline`: additive public context entry point; engine still owns font metrics, atlas texture, and geometry storage.
- Four text tests covering UTF-8 boundaries/malformed input, fallback measurement, UV geometry/batching, and logical rollback on capacity failure.

## Contracts

- UTF-8 rejects overlong encodings, surrogate scalars, truncated/invalid continuation sequences, and values above U+10FFFF.
- Missing codepoints use `Font.fallback`; absence of both glyph and fallback returns `error.MissingGlyph`.
- `scale` must be finite and positive; baseline coordinates must be finite.
- Geometry for a failed string is logically atomic: public counts and the previous merged command are restored. Bytes written beyond restored counts are unreachable through the draw view and may be overwritten later.
- No allocator, rasterizer, OS, renderer, or GPU API is introduced.
- Newline/multiline policy remains intentionally outside this stage; this API emits one baseline run.

## Validation status

Static inspection only in this environment. Zig 0.17.0 was not available locally, so formatting, compilation, unit tests, integration, and benchmarks must be executed before this stage is considered validated.
