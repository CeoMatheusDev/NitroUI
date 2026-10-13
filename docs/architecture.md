# Architecture and ownership

NitroUI is a **100% Zig**, engine-first, immediate-mode UI core.

## Boundaries

The host engine provides the window, input events, timing, display size, textures, renderer, and storage. NitroUI processes input and produces geometry, index data, commands, and clip regions. It does not call a GPU or operating-system API.

## Core modules

| Module | Responsibility |
| --- | --- |
| `root.zig` | Public module and context integration |
| `memory.zig` | Caller-provided storage and arenas |
| `input.zig` | Input event handling |
| `ids.zig` | Hierarchical widget identifiers |
| `state.zig` | Persistent widget state |
| `draw.zig` | Geometry and draw commands |
| `clip.zig` | Clipping support |

## Lifecycle

`idle → building → ready → idle` corresponds to `beginFrame()`, `endFrame()`, and `releaseFrame()`. The renderer consumes a borrowed view during `ready`.

## Invariants

- Storage is supplied by the engine and must not overlap across attached regions.
- Frame-bound scratch data expires when a new frame begins.
- Draw-data views are valid only while the frame is ready.
- Storage exhaustion returns `error.OutOfCapacity`.
- Invalid lifecycle operations return `error.InvalidFrameState`.
- No global mutable UI context is required.

Consult the public API and tests for exact storage attachment and lifetime requirements.
