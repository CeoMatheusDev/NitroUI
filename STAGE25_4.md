# Stage 25.4 — Text measurement integrated into vertical layout

- Added `layout.Stack.nextText(font, utf8, scale)`: measures a single line using `text.measure` and computes line height from the font's ascent, descent and line gap. It then delegates placement to the existing `next` operation.
- Added `Context.nextTextLayoutRect` (building state only), with a documented baseline formula for `drawTextBaseline`.
- No font rasterization, wrapping, geometry emission, new storage, or changes to existing APIs.
- Two tests cover metrics, spacing, missing glyph, malformed UTF-8, invalid scale and cursor preservation.
- **Validation pending:** Zig 0.17.0 unavailable in this execution environment; compilation and test results are not claimed.
- **Precondition:** fonts supplied by the engine must have passed `Font.validate` before use. `nextText` does not validate font glyph tables each call.
- **Known limitations:** single-line only, no clipping or wrapping; caller decides overflow policy and performs draw emission separately. `nextText` does not make layout reservation and subsequent draw emission transactional as a combined operation.
