# NitroUI

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
zig fmt build.zig src bench
zig fmt --check build.zig src bench
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

- Widgets: `button`, `checkbox`, `sliderFloat`; no text/fonts yet.
- No measured clicks, keyboard/unicode, long/varied string labels, or
  non-rectangle primitive timing.
- Zero post-warm-up allocations hold structurally (no allocator parameters)
  and operationally (stable buffer reuse over 40 mixed frames); heap-counter
  verification is inapplicable by construction.
- `examples/engine_host.zig` exercises the engine-side contract headlessly
  (40 frames, renderer checks, buffer reuse) but consumes synchronously: it
  does not cover async GPU submission or a real engine.
- Do not mutate `Context` fields directly; use the API. Do not publish
  expectations about version 0.2.0 until the criteria in the project stages
  are demonstrated. See `STAGE*.md` for history.
