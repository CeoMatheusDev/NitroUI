# NitroUI

**Native Zig · Engine-first · Backend-independent**

NitroUI is an experimental immediate-mode UI library written in Zig, designed for integration into game engines and custom renderers. The engine owns memory, input, timing, and GPU submission; NitroUI produces draw data.

**Current package version:** `0.2.0` · **Required Zig:** `0.17.0`

[![CI](https://github.com/CeoMatheusDev/NitroUI/actions/workflows/ci.yml/badge.svg)](https://github.com/CeoMatheusDev/NitroUI/actions/workflows/ci.yml)

> **Status:** Experimental. No stable API guarantee or production-readiness claim. No 2.0.0 release has been published by this documentation change.

## Design principles

- **100% Zig:** no C/C++ layer or mandatory external dependencies.
- **Engine-first:** no direct windowing, operating-system, input-device, or GPU API access.
- **Explicit ownership:** the engine supplies disjoint buffers; the UI core does not take `std.mem.Allocator`.
- **Predictable frame lifecycle:** invalid transitions return `error.InvalidFrameState`.
- **Renderer independence:** output is vertices, indices, draw commands, and clip regions.
- **Instance-local state:** one `Context` per UI instance; no required mutable globals.

## Responsibility boundary

| Engine supplies | NitroUI supplies |
| --- | --- |
| Window, events, frame timing, display size | Input processing and frame context |
| GPU resources, textures, renderer | Geometry, draw commands and clipping |
| Caller-owned storage | IDs, persistent widget state, layout and widgets |

## Getting started

```sh
git clone https://github.com/CeoMatheusDev/NitroUI.git
cd NitroUI
zig version  # expected: 0.17.0
zig build
zig build test
zig build integration
zig fmt --check build.zig src bench examples
```

### Integrate as a local Zig module

Place NitroUI at `engine/third_party/nitro_ui/`, then add the dependency to your engine's `build.zig.zon`:

```zig
.dependencies = .{
    .nitro_ui = .{ .path = "third_party/nitro_ui" },
},
```

In your engine's `build.zig`, import its public module:

```zig
const nitro_ui = b.dependency("nitro_ui", .{
    .target = target,
    .optimize = optimize,
});
mod.addImport("nitro_ui", nitro_ui.module("nitro_ui"));
```

Use `@import("nitro_ui")` in application code. See `examples/engine_host.zig` for a headless consumer of the public module.

## Frame lifecycle

```text
idle → beginFrame → building → endFrame → ready → releaseFrame → idle
```

Storage must be attached before use. A renderer may consume the borrowed draw-data view only while the frame is ready; do not mutate or reuse its backing buffers until `releaseFrame()`. Unbalanced layout, ID, or clipping scopes are reported at frame end.

## Current capabilities and limits

The current API includes input handling, hierarchical IDs, persistent state, layout, clipping, geometry, and `button`, `checkbox`, and `sliderFloat` widgets.

**Not yet covered:** text/fonts, full keyboard/Unicode interaction, real GPU integration, and asynchronous GPU submission. The headless integration example tests an engine-side contract, not an actual rendering backend.

## Verification and benchmarking

```sh
zig build test --summary all
zig build integration -Doptimize=ReleaseFast
zig build bench -Doptimize=ReleaseFast
```

The benchmark measures deterministic geometry and widget scenarios. Treat results as environment-specific, not as universal performance guarantees.

## Documentation

- [Architecture and ownership](docs/architecture.md)
- [Versioning and releases](docs/versioning.md)
- [Changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

## License

**Not yet selected.** No open-source license is granted merely by making a repository public. A license file should be added after the copyright holder chooses the terms.
