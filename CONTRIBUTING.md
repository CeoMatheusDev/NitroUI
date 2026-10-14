# Contributing to NitroUI

NitroUI is an experimental **Zig 0.17.0** engine-first immediate-mode UI library.

## Workflow

1. Open an issue for substantial API or architectural changes.
2. Branch from `main` and keep each change focused.
3. Preserve explicit ownership, deterministic errors, and the engine/backend boundary.
4. Do not introduce mandatory external dependencies, C/C++ bindings, platform windowing, or GPU API calls.
5. Explain memory lifetime, capacity failure behavior, and performance trade-offs in your pull request.

## Local checks

```sh
zig version
zig fmt --check build.zig src bench examples
zig build
zig build test
zig build integration
```

Run `zig build integration -Doptimize=ReleaseFast` for changes to frame lifecycle, geometry, or public API. Include benchmark commands, machine details, and before/after numbers for performance claims.

## Compatibility

The package is pre-1.0 and APIs may change. Document breaking changes and update `CHANGELOG.md`; do not change `build.zig.zon` version without an intentional release decision.

## Licensing

A project license has not yet been selected. Discuss licensing before submitting external contributions.
