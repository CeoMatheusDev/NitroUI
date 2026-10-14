# Contributing to NitroUI

NitroUI targets **Zig 0.17.0** and is designed to be engine-first and backend-independent.

## Before submitting a change

1. Keep changes narrowly scoped and preserve existing public contracts.
2. Do not introduce mandatory dependencies, C/C++ bindings, OS APIs, or GPU calls.
3. Run `zig fmt --check build.zig src` and `zig build test` using Zig 0.17.0.
4. Describe memory ownership, error behavior, and any performance implications.
5. Never claim benchmark improvements without reproducible measurements.

The project is experimental; its existing source has not yet been compiler-verified with Zig 0.17.0.
