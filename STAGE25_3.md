# Stage 25.3 — Unicode and text emission regression hardening

Baseline: stage 25.2 ZIP, **not** the GitHub `main` branch. Declared version remains `0.2.0`.

## Repository inspection

GitHub `main` was inspected using the connected GitHub repository interface. It still exposes the 10 pre-font `src` modules and the older CI; `font.zig` and `text.zig` are local-only at the time of this inspection. No remote changes were made.

## Changes

- `src/text.zig`: export the UTF-8 decoder result type (`Decoded`) for its public return contract.
- `src/text.zig`: validate public geometry counters before reading the previous draw command for rollback, preventing an out-of-bounds read when `command_count` was corrupted.
- `src/text.zig`: reject non-finite pen positions during text emission.
- Five additional regression tests: Unicode boundaries and malformed UTF-8; empty/invalid text; rollback of a pre-existing merged command; corrupt public counter; non-finite coordinates.
- No modifications to `draw.Vertex`, `draw.Command`, or existing public function signatures; no new dependencies or allocations.

## Validation and remaining risks

Static inspection and ZIP integrity checks only. The Zig 0.17.0 compiler is not installed in this execution environment; compilation, formatting and tests **have not been executed**. The expected test count is 94 if all earlier 89 tests are present and discovered, but this is unverified.

The text implementation intentionally does not perform font shaping, bidi, kerning, multiline layout, wrapping or GPU submission. Fonts are borrowed; the caller must validate font data and keep it immutable. Text emission currently performs a measurement pass and an emission pass; this favors logical atomicity over minimum traversal cost. The public draw counters are still mutable by callers, so validation remains important.

Next: run Zig 0.17.0 Debug/ReleaseFast test matrix and integration on Fedora; fix failures before 25.4 layout integration. Do not publish v0.3.0 or change remote without authorization.
