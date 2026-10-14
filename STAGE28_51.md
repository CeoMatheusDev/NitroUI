# NitroUI — Stage 28.51

## Scope
Added a regression test for the distinction between *overlapping destination bytes* and *sharing a backing allocation* during UTF-8 editor initialization.

- Source in the unused tail of caller storage is disjoint from the destination prefix and is safe to copy.
- Source overlapping the written destination prefix must fail with `InvalidCursor` without changing storage.
- Tests also check UTF-8 validity, cursor and selection after the successful copy.

No runtime or public API changes. Version stays 0.2.0.

## Validation
Shell syntax and mocked validation harness can be executed without Zig. Zig 0.17.0 was not available in this environment; the new Zig test was **not compiled or run**. No performance claims or benchmarks.
