# NitroUI

[![CI](https://github.com/CeoMatheusDev/NitroUI/actions/workflows/ci.yml/badge.svg)](https://github.com/CeoMatheusDev/NitroUI/actions/workflows/ci.yml)

Immediate-mode UI library in native Zig, engine-first and backend-independent.
100% Zig 0.17.0. No C/C++, no OS/window/input/GPU access, no mandatory
external dependencies.

Version: 0.2.0.

> Native Zig. Engine-First. Performance-Driven.

## Responsibilities

| Engine provides | NitroUI provides |
|---|---|
| Window, OS, input events, delta time, display size | Frame context, input processing, IDs, persistent state |
| Textures, renderer, GPU, graphics backend | Layout, widgets, interaction, style, geometry |
| Caller-owned buffers (all memory) | Draw data (vertices, indices, commands, clips) |

NitroUI never allocates on the hot path: every buffer is caller-owned and
attached explicitly. No function takes `std.mem.Allocator`.

## Integration as a local module

Vendor under your engine and add a path dependency:

```zig
// engine/build.zig.zon
.dependencies = .{
    .nitro_ui = .{ .path = "third_party/nitro_ui" },
},
```

```zig
// engine/build.zig
const nitro_ui = b.dependency("nitro_ui", .{
    .target = target,
    .optimize = optimize,
});
mod.addImport("nitro_ui", nitro_ui.module("nitro_ui"));
```

```zig
const ui = @import("nitro_ui");
```

Requires Zig 0.17.0 (`zig version`). Single-threaded; one `Context` per
instance, no global mutable state.

## Frame cycle

```zig
var vertices: [256]ui.draw.Vertex = undefined;
var indices: [384]u32 = undefined;
var commands: [16]ui.draw.Command = undefined;
var ctx: ui.Context = .{};
try ctx.setGeometryStorage(&vertices, &indices, &commands);

var checked: bool = false;
var volume: f32 = 0.5;
const region: ui.draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 800, .max_y = 600 };

try ctx.beginFrame(.{ .delta_seconds = 1.0 / 60.0, .display_size = .{ .x = 800, .y = 600 } });
try ctx.processEvents(&.{.{ .pointer_move = .{ .x = 40, .y = 30 } }});
try ctx.pushLayout(.{ .x = 10, .y = 10, .width = 200, .height = 200 }, .{ .x = 0, .y = 6 });
const b = try ctx.nextLayoutRect(null, 28);
const c = try ctx.nextLayoutRect(null, 20);
const s = try ctx.nextLayoutRect(null, 20);
if (try ctx.button(try ctx.widgetId("play"), b, region)) {}
_ = try ctx.checkbox(try ctx.widgetId("muted"), c, &checked, region);
_ = try ctx.sliderFloat(try ctx.widgetId("volume"), s, &volume, 0, 1, region);
try ctx.popLayout();
try ctx.endFrame();

// Renderer consumes the borrowed view, then the frame is released.
const view = try ctx.drawDataView();
// ... submit view.vertices / view.indices / view.commands to the GPU ...
try ctx.releaseFrame();
```

States: `idle → beginFrame → building → endFrame → ready → releaseFrame → idle`.
Calls incompatible with the current state return `error.InvalidFrameState`.
Unbalanced ID scopes, clips or layout regions fail `endFrame()` and keep the
`building` state so the frame can be finished or abandoned explicitly.

## Ownership and slice validity

| Data | Owner | Valid |
|---|---|---|
| Scratch/persistent/render arenas, state entries, geometry buffers, ID-tracking storage | Engine (attached idle-only, must be pairwise disjoint) | Until replaced/detached |
| `reserveScratch` slices | Context arena | Until next `beginFrame()` |
| `reserveRender` slices, `drawDataView()` slices | Context arena / geometry | `ready` only, until `releaseFrame()` |
| `reservePersistent` slices, `widgetState()` entries | Context arena / state table | Across frames, until storage replaced (`pruneStates` may move entries) |
| Event batches passed to `processEvents` | Engine | Until next batch or frame release |

`[]const` on the draw view forbids writes through that reference but does not
remove other mutable aliases: do not mutate or reuse the storage while the
renderer consumes it. Capacity exhaustion returns `error.OutOfCapacity`
without partial writes (widgets roll back logically). Calling `widgetState`
or any `reserve*` before attaching the corresponding storage returns
`error.MissingStorage` instead.

## Build, test, benchmark

```sh
zig version                                   # 0.17.0
zig fmt build.zig src bench examples
zig fmt --check build.zig src bench examples
zig build test --summary all                  # 82/82 (Debug and ReleaseFast)
zig test src/root.zig                         # 82/82
zig build integration                         # headless engine-side contract (Debug)
zig build integration -Doptimize=ReleaseFast  # headless engine-side contract
zig build bench -Doptimize=ReleaseFast
```

The headless bench runs deterministic `rect` (geometry only), `widget`
(input + layout + integer-ID buttons) and `idstr` (hierarchical string IDs)
cases with 30 warm-up and 300 measured frames, reporting checksums plus
`ns_frame_min/med/p90/max` and `ns_widget_med`.
Reference machine-specific medians: ~14ns/widget (`rect`), ~30ns/widget
(`widget`), ~32ns/widget (`idstr`), linear from 64 to 4096 widgets.
Your numbers will differ. A steady-state integration test additionally proves
stable high-watermarks and exact output over 40 mixed frames after warm-up.

## Engine-side integration contract (headless)

Run `zig build integration` or `zig build integration -Doptimize=ReleaseFast`.
`examples/engine_host.zig` is an independent consumer of the public module:
it simulates an engine supplying input/time/storage and a synchronous renderer
checking index ranges, clipping, texture handles and frame reuse for 40 frames.
It does **not** exercise an actual engine or asynchronous GPU submission.

## Limitations (0.2.0)

- Widgets include `button`, `checkbox`, and `sliderFloat`. The codebase also contains font, text rendering, text editing, and text input modules.
- Performance measurements do not yet comprehensively cover clicks,
  keyboard/Unicode input, long or varied string labels, or
  non-rectangle primitives.
- Zero post-warm-up allocations hold structurally (no allocator parameters)
  and operationally (stable buffer reuse over 40 mixed frames); heap-counter
  verification is inapplicable by construction.
- `examples/engine_host.zig` exercises the engine-side contract headlessly
  (40 frames, renderer checks, buffer reuse) but consumes synchronously: it
  does not cover async GPU submission or a real engine.
- Do not mutate `Context` fields directly; use the API.
- The 0.2.0 tag documents the baseline; development-stage changes must be
  validated separately before inclusion in a future release. See `STAGE*.md`.

## Development after the 0.2.0 baseline

Development after the 0.2.0 baseline includes font and glyph metadata,
UTF-8 text measurement and drawing, text editing, and keyboard-driven text
input modules. These capabilities are still experimental and do not imply
complete font rasterization, Unicode coverage, or production-ready text widgets.

The repository retains package version 0.2.0 until an explicit release
decision. The integrated development snapshot has been validated locally
with Zig 0.17.0, including builds, tests, headless integration, and benchmark
execution. Local validation does not establish that GitHub Actions has passed.

CI is configured to check formatting, unit tests in Debug/ReleaseFast,
headless integration in both modes, and the ReleaseFast benchmark.
A configured CI job is not evidence that a run passed.

## Documentation

- [Architecture and ownership](docs/architecture.md)
- [Versioning and releases](docs/versioning.md)
- [Changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

## Project status

NitroUI is experimental. Its public API may change, and production readiness
is not guaranteed.

The repository currently retains package version 0.2.0. Development stages
after the 0.2.0 baseline do not constitute a new published release.

## License

No open-source license has been selected yet. Making a repository public
does not automatically grant permission to reuse or redistribute its code.
