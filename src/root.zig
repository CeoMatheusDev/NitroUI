//! NitroUI: engine-first immediate-mode UI contracts.
//! Initial milestone: frame lifecycle and input/display boundary only.

const std = @import("std");
pub const memory = @import("memory.zig");
pub const input_events = @import("input.zig");
pub const ids = @import("ids.zig");
pub const widget_state = @import("state.zig");
pub const draw = @import("draw.zig");
pub const clip = @import("clip.zig");

pub const FrameState = enum { idle, building, ready };

pub const Vec2 = struct {
    x: f32,
    y: f32,
};

pub const FrameInput = struct {
    delta_seconds: f32,
    display_size: Vec2,
    mouse_position: Vec2 = .{ .x = 0, .y = 0 },
    mouse_primary_down: bool = false,
};

pub const Error = error{
    InvalidFrameState,
    InvalidDeltaTime,
    InvalidDisplaySize,
    FrameCounterOverflow,
    OverlappingBuffers,
    AddressOverflow,
    MissingGeometry,
};

/// A context is owned by its caller; no global mutable state.
/// This milestone performs no heap allocations.
pub const Context = struct {
    state: FrameState = .idle,
    frame_number: u64 = 0,
    input: ?FrameInput = null,
    scratch: ?memory.ByteArena = null,
    render: ?memory.ByteArena = null,
    persistent: ?memory.ByteArena = null,
    input_processor: input_events.Processor = .{},
    id_stack: ids.Stack = ids.Stack.init(),
    states: ?widget_state.Table = null,
    geometry: ?draw.Buffer = null,
    clip_stack: clip.Stack = .{},

    /// Attach engine-owned typed geometry buffers while idle.
    /// Their storage must remain valid until detached; geometry is valid in ready.
    pub fn setGeometryStorage(self: *Context, vertices: []draw.Vertex, indices: []u32, commands: []draw.Command) Error!void {
        if (self.state != .idle) return error.InvalidFrameState;
        const v = std.mem.sliceAsBytes(vertices);
        const i = std.mem.sliceAsBytes(indices);
        const c = std.mem.sliceAsBytes(commands);
        try ensureDisjoint(v, i);
        try ensureDisjoint(v, c);
        try ensureDisjoint(i, c);
        if (self.scratch) |arena| {
            try ensureDisjoint(v, arena.storage);
            try ensureDisjoint(i, arena.storage);
            try ensureDisjoint(c, arena.storage);
        }
        if (self.render) |arena| {
            try ensureDisjoint(v, arena.storage);
            try ensureDisjoint(i, arena.storage);
            try ensureDisjoint(c, arena.storage);
        }
        if (self.persistent) |arena| {
            try ensureDisjoint(v, arena.storage);
            try ensureDisjoint(i, arena.storage);
            try ensureDisjoint(c, arena.storage);
        }
        if (self.states) |table| {
            const bytes = std.mem.sliceAsBytes(table.entries);
            try ensureDisjoint(v, bytes);
            try ensureDisjoint(i, bytes);
            try ensureDisjoint(c, bytes);
        }
        self.geometry = draw.Buffer.init(vertices, indices, commands);
    }

    pub fn drawRect(self: *Context, x0: f32, y0: f32, x1: f32, y1: f32, color: u32, texture: u64, clip_rect: draw.ClipRect) (Error || draw.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.geometry) |*buffer| return buffer.addRect(x0, y0, x1, y1, color, texture, clip_rect);
        return error.MissingGeometry;
    }

    /// Append a filled triangle to the current frame.
    pub fn drawTriangle(self: *Context, a: [2]f32, b: [2]f32, c: [2]f32, color: u32, texture: u64, clip_rect: draw.ClipRect) (Error || draw.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.geometry) |*buffer| return buffer.addTriangle(a, b, c, color, texture, clip_rect);
        return error.MissingGeometry;
    }

    pub fn drawLine(self: *Context, a: [2]f32, b: [2]f32, thickness: f32, color: u32, texture: u64, region: draw.ClipRect) (Error || draw.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.geometry) |*buffer| return buffer.addLine(a, b, thickness, color, texture, region);
        return error.MissingGeometry;
    }

    pub fn drawCircle(self: *Context, center: [2]f32, radius: f32, segments: u16, color: u32, texture: u64, region: draw.ClipRect) (Error || draw.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.geometry) |*buffer| return buffer.addCircle(center, radius, segments, color, texture, region);
        return error.MissingGeometry;
    }

    /// Push a nested clip rectangle; intersected with the current parent.
    pub fn pushClip(self: *Context, rect: draw.ClipRect) (Error || clip.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        try self.clip_stack.push(rect);
    }

    pub fn popClip(self: *Context) (Error || clip.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        try self.clip_stack.pop();
    }

    /// Draw using the active clip stack. Explicit-clip APIs remain unchanged.
    pub fn drawRectClipped(self: *Context, x0: f32, y0: f32, x1: f32, y1: f32, color: u32, texture: u64) (Error || draw.Error || clip.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        const rect = self.clip_stack.current() orelse return error.InvalidClip;
        try self.drawRect(x0, y0, x1, y1, color, texture, rect);
    }

    pub fn drawTriangleClipped(self: *Context, a: [2]f32, b: [2]f32, c: [2]f32, color: u32, texture: u64) (Error || draw.Error || clip.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        const rect = self.clip_stack.current() orelse return error.InvalidClip;
        try self.drawTriangle(a, b, c, color, texture, rect);
    }

    pub fn drawLineClipped(self: *Context, a: [2]f32, b: [2]f32, thickness: f32, color: u32, texture: u64) (Error || draw.Error || clip.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        const region = self.clip_stack.current() orelse return error.InvalidClip;
        try self.drawLine(a, b, thickness, color, texture, region);
    }

    pub fn drawCircleClipped(self: *Context, center: [2]f32, radius: f32, segments: u16, color: u32, texture: u64) (Error || draw.Error || clip.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        const region = self.clip_stack.current() orelse return error.InvalidClip;
        try self.drawCircle(center, radius, segments, color, texture, region);
    }

    /// Read-only geometry view, available only after endFrame and before releaseFrame.
    pub fn drawData(self: *const Context) Error!draw.Buffer {
        if (self.state != .ready) return error.InvalidFrameState;
        return self.geometry orelse error.MissingGeometry;
    }

    /// Caller owns the typed state storage; valid for the context lifetime.
    /// Must not overlap any other active storage. Configuration is idle-only.
    pub fn setStateStorage(self: *Context, storage: []widget_state.Entry) (Error || widget_state.Error)!void {
        if (self.state != .idle) return error.InvalidFrameState;
        const size = @mulWithOverflow(storage.len, @sizeOf(widget_state.Entry));
        if (size[1] != 0) return error.AddressOverflow;
        const bytes = @as([*]u8, @ptrCast(storage.ptr))[0..size[0]];
        if (self.scratch) |arena| try ensureDisjoint(bytes, arena.storage);
        if (self.render) |arena| try ensureDisjoint(bytes, arena.storage);
        if (self.persistent) |arena| try ensureDisjoint(bytes, arena.storage);
        if (self.geometry) |g| try ensureGeometryDisjoint(bytes, g);
        self.states = try widget_state.Table.init(storage);
    }

    /// Returns a mutable entry whose value survives frame transitions.
    pub fn widgetState(self: *Context, id: ids.Id) (Error || widget_state.Error)!*widget_state.Entry {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.states) |*table| return table.getOrPut(id, self.frame_number);
        return error.OutOfCapacity;
    }

    /// Explicit maintenance, never executed implicitly on the hot path.
    pub fn pruneStates(self: *Context, min_frame: u64) Error!void {
        if (self.state != .idle) return error.InvalidFrameState;
        if (self.states) |*table| table.prune(min_frame);
    }

    /// Attach caller-owned buffers while idle. Overlap is rejected.
    /// Buffers must remain alive until detached/replaced or context destruction.
    pub fn setBuffers(self: *Context, scratch_storage: []u8, render_storage: []u8) Error!void {
        if (self.state != .idle) return error.InvalidFrameState;
        try ensureDisjoint(scratch_storage, render_storage);
        if (self.persistent) |arena| {
            try ensureDisjoint(scratch_storage, arena.storage);
            try ensureDisjoint(render_storage, arena.storage);
        }
        if (self.states) |table| {
            const bytes = @as([*]const u8, @ptrCast(table.entries.ptr))[0 .. table.entries.len * @sizeOf(widget_state.Entry)];
            try ensureDisjoint(scratch_storage, bytes);
            try ensureDisjoint(render_storage, bytes);
        }
        if (self.geometry) |g| {
            try ensureGeometryDisjoint(scratch_storage, g);
            try ensureGeometryDisjoint(render_storage, g);
        }
        self.scratch = memory.ByteArena.init(scratch_storage);
        self.render = memory.ByteArena.init(render_storage);
    }

    /// Attach persistent caller-owned memory. Contents survive frame transitions.
    /// Reattaching replaces the arena and invalidates previous persistent slices.
    pub fn setPersistentBuffer(self: *Context, storage: []u8) Error!void {
        if (self.state != .idle) return error.InvalidFrameState;
        if (self.scratch) |arena| try ensureDisjoint(storage, arena.storage);
        if (self.render) |arena| try ensureDisjoint(storage, arena.storage);
        if (self.states) |table| {
            const bytes = @as([*]const u8, @ptrCast(table.entries.ptr))[0 .. table.entries.len * @sizeOf(widget_state.Entry)];
            try ensureDisjoint(storage, bytes);
        }
        if (self.geometry) |g| try ensureGeometryDisjoint(storage, g);
        self.persistent = memory.ByteArena.init(storage);
    }

    /// Persistent bytes survive frames, until the buffer is replaced or destroyed.
    /// Reservations are only permitted during the building phase.
    pub fn reservePersistent(self: *Context, count: usize) (Error || memory.Error)![]u8 {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.persistent) |*arena| return arena.reserve(count);
        return error.OutOfCapacity;
    }

    /// Aligned persistent storage. Padding is charged to the persistent arena.
    pub fn reservePersistentAligned(self: *Context, count: usize, alignment: usize) (Error || memory.Error)![]u8 {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.persistent) |*arena| return arena.reserveAligned(count, alignment);
        return error.OutOfCapacity;
    }

    /// Aligned scratch storage. Valid until the next beginFrame().
    pub fn reserveScratchAligned(self: *Context, count: usize, alignment: usize) (Error || memory.Error)![]u8 {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.scratch) |*arena| return arena.reserveAligned(count, alignment);
        return error.OutOfCapacity;
    }

    /// Aligned render storage. Must not be accessed after releaseFrame().
    pub fn reserveRenderAligned(self: *Context, count: usize, alignment: usize) (Error || memory.Error)![]u8 {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.render) |*arena| return arena.reserveAligned(count, alignment);
        return error.OutOfCapacity;
    }

    /// Frame-temporary bytes, invalidated at the next beginFrame().
    pub fn reserveScratch(self: *Context, count: usize) (Error || memory.Error)![]u8 {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.scratch) |*arena| return arena.reserve(count);
        return error.OutOfCapacity;
    }

    /// Render bytes remain valid through ready, until releaseFrame().
    pub fn reserveRender(self: *Context, count: usize) (Error || memory.Error)![]u8 {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.render) |*arena| return arena.reserve(count);
        return error.OutOfCapacity;
    }

    pub fn beginFrame(self: *Context, input: FrameInput) Error!void {
        if (self.state != .idle) return error.InvalidFrameState;
        if (!isFinite(input.delta_seconds) or input.delta_seconds < 0)
            return error.InvalidDeltaTime;
        if (!isFinite(input.display_size.x) or !isFinite(input.display_size.y) or
            input.display_size.x <= 0 or input.display_size.y <= 0)
            return error.InvalidDisplaySize;
        if (self.frame_number == ~@as(u64, 0)) return error.FrameCounterOverflow;
        if (self.geometry) |*buffer| buffer.reset();
        if (self.scratch) |*arena| arena.reset();
        if (self.render) |*arena| arena.reset();
        self.input = input;
        self.input_processor.beginFrame();
        self.id_stack.reset();
        self.clip_stack.reset();
        self.state = .building;
    }

    /// Process an ordered batch. Event slices must remain valid until the next batch
    /// or frame release; the engine owns their storage.
    pub fn processEvents(self: *Context, events: []const input_events.Event) (Error || input_events.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        try self.input_processor.process(events);
    }

    /// Widget IDs are only valid to request while constructing a frame.
    pub fn widgetId(self: *const Context, label: []const u8) (Error)!ids.Id {
        if (self.state != .building) return error.InvalidFrameState;
        return self.id_stack.idString(label);
    }

    pub fn pushId(self: *Context, label: []const u8) (Error || ids.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        try self.id_stack.pushString(label);
    }

    pub fn pushIdInteger(self: *Context, value: u64) (Error || ids.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        try self.id_stack.pushInteger(value);
    }

    pub fn popId(self: *Context) (Error || ids.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        try self.id_stack.pop();
    }

    pub fn endFrame(self: *Context) (Error || ids.Error || clip.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        try self.id_stack.validateBalanced();
        try self.clip_stack.validateBalanced();
        self.state = .ready;
        self.frame_number += 1;
    }

    /// Signals that the engine has finished consuming frame data.
    pub fn releaseFrame(self: *Context) Error!void {
        if (self.state != .ready) return error.InvalidFrameState;
        self.state = .idle;
        self.input = null;
    }
};

fn ensureGeometryDisjoint(bytes: []const u8, g: draw.Buffer) Error!void {
    try ensureDisjoint(bytes, std.mem.sliceAsBytes(g.vertices));
    try ensureDisjoint(bytes, std.mem.sliceAsBytes(g.indices));
    try ensureDisjoint(bytes, std.mem.sliceAsBytes(g.commands));
}

/// Half-open address intervals; empty slices never overlap.
/// Checked arithmetic prevents wrapping the address interval.
fn ensureDisjoint(a: []const u8, b: []const u8) Error!void {
    if (a.len == 0 or b.len == 0) return;
    const a_start = @intFromPtr(a.ptr);
    const b_start = @intFromPtr(b.ptr);
    const a_end = @addWithOverflow(a_start, a.len);
    const b_end = @addWithOverflow(b_start, b.len);
    if (a_end[1] != 0 or b_end[1] != 0) return error.AddressOverflow;
    if (a_start < b_end[0] and b_start < a_end[0]) return error.OverlappingBuffers;
}

fn isFinite(x: f32) bool {
    // NaN fails equality; infinities are excluded by magnitude.
    return x == x and @abs(x) <= 3.402823466e38;
}

test "frame lifecycle" {
    const testing = @import("std").testing;
    var ctx: Context = .{};
    const input: FrameInput = .{
        .delta_seconds = 1.0 / 60.0,
        .display_size = .{ .x = 1280, .y = 720 },
    };
    try testing.expectError(error.InvalidFrameState, ctx.endFrame());
    try ctx.beginFrame(input);
    try testing.expectError(error.InvalidFrameState, ctx.beginFrame(input));
    try ctx.endFrame();
    try testing.expectEqual(@as(u64, 1), ctx.frame_number);
    try ctx.releaseFrame();
    try testing.expectEqual(FrameState.idle, ctx.state);
}

test "invalid frame input leaves context unchanged" {
    const testing = @import("std").testing;
    var ctx: Context = .{};
    try testing.expectError(error.InvalidDisplaySize, ctx.beginFrame(.{
        .delta_seconds = 0.016,
        .display_size = .{ .x = 0, .y = 720 },
    }));
    try testing.expectEqual(FrameState.idle, ctx.state);
    try testing.expectError(error.InvalidDeltaTime, ctx.beginFrame(.{
        .delta_seconds = -1,
        .display_size = .{ .x = 100, .y = 100 },
    }));
}

test "render memory survives until release and ready cannot be overwritten" {
    const testing = @import("std").testing;
    var scratch: [16]u8 = undefined;
    var render: [32]u8 = undefined;
    var ctx: Context = .{};
    try ctx.setBuffers(&scratch, &render);
    const input: FrameInput = .{
        .delta_seconds = 0.016,
        .display_size = .{ .x = 800, .y = 600 },
    };
    try ctx.beginFrame(input);
    const bytes = try ctx.reserveRender(4);
    bytes[0] = 42;
    _ = try ctx.reserveScratch(8);
    try ctx.endFrame();
    try testing.expectEqual(@as(u8, 42), bytes[0]);
    try testing.expectError(error.InvalidFrameState, ctx.beginFrame(input));
    try testing.expectError(error.InvalidFrameState, ctx.reserveRender(1));
    try ctx.releaseFrame();
    try ctx.beginFrame(input);
    try testing.expectEqual(@as(usize, 0), ctx.render.?.used);
    try testing.expectEqual(@as(usize, 0), ctx.scratch.?.used);
}

test "buffer overlap rejected transactionally" {
    const testing = @import("std").testing;
    var bytes: [64]u8 = undefined;
    var ctx: Context = .{};
    try testing.expectError(error.OverlappingBuffers, ctx.setBuffers(bytes[0..32], bytes[16..48]));
    try testing.expect(ctx.scratch == null);
    try testing.expect(ctx.render == null);
    try ctx.setBuffers(bytes[0..16], bytes[16..32]);
    try testing.expectError(error.OverlappingBuffers, ctx.setPersistentBuffer(bytes[8..24]));
    try testing.expect(ctx.persistent == null);
    try ctx.setPersistentBuffer(bytes[32..64]);
    try testing.expectError(error.OverlappingBuffers, ctx.setBuffers(bytes[0..16], bytes[48..64]));
    try testing.expectEqual(@as(usize, 16), ctx.render.?.storage.len);
}

test "persistent arena survives frames and capacity failure" {
    const testing = @import("std").testing;
    var bytes: [12]u8 = undefined;
    var ctx: Context = .{};
    try ctx.setPersistentBuffer(&bytes);
    const input: FrameInput = .{
        .delta_seconds = 0.016,
        .display_size = .{ .x = 640, .y = 480 },
    };
    try ctx.beginFrame(input);
    const stored = try ctx.reservePersistent(8);
    stored[0] = 77;
    try testing.expectError(error.OutOfCapacity, ctx.reservePersistent(5));
    try testing.expectEqual(@as(usize, 8), ctx.persistent.?.used);
    try ctx.endFrame();
    try ctx.releaseFrame();
    try ctx.beginFrame(input);
    try testing.expectEqual(@as(u8, 77), stored[0]);
    try testing.expectEqual(@as(usize, 8), ctx.persistent.?.used);
    _ = try ctx.reservePersistent(4);
    try testing.expectError(error.OutOfCapacity, ctx.reservePersistent(1));
}

test "persistent mutation rejected while frame is ready" {
    const testing = @import("std").testing;
    var bytes: [8]u8 = undefined;
    var ctx: Context = .{};
    try ctx.beginFrame(.{ .delta_seconds = 0, .display_size = .{ .x = 1, .y = 1 } });
    try testing.expectError(error.InvalidFrameState, ctx.setPersistentBuffer(&bytes));
    try ctx.endFrame();
    try testing.expectError(error.InvalidFrameState, ctx.reservePersistent(1));
}

test "context aligned reservations preserve frame boundaries" {
    const testing = @import("std").testing;
    var scratch: [128]u8 = undefined;
    var render: [128]u8 = undefined;
    var persistent: [128]u8 = undefined;
    var ctx: Context = .{};
    try ctx.setBuffers(&scratch, &render);
    try ctx.setPersistentBuffer(&persistent);
    const input: FrameInput = .{ .delta_seconds = 0.016, .display_size = .{ .x = 640, .y = 480 } };
    try testing.expectError(error.InvalidFrameState, ctx.reserveScratchAligned(8, 16));
    try ctx.beginFrame(input);
    const a = try ctx.reserveScratchAligned(16, 16);
    const b = try ctx.reserveRenderAligned(16, 32);
    const c = try ctx.reservePersistentAligned(16, 8);
    try testing.expectEqual(@as(usize, 0), @intFromPtr(a.ptr) & 15);
    try testing.expectEqual(@as(usize, 0), @intFromPtr(b.ptr) & 31);
    try testing.expectEqual(@as(usize, 0), @intFromPtr(c.ptr) & 7);
    c[0] = 42;
    try ctx.endFrame();
    try testing.expectError(error.InvalidFrameState, ctx.reserveRenderAligned(1, 8));
    try ctx.releaseFrame();
    try ctx.beginFrame(input);
    try testing.expectEqual(@as(u8, 42), c[0]);
    try testing.expectEqual(@as(usize, 0), ctx.render.?.used);
    try testing.expectEqual(@as(usize, 0), ctx.scratch.?.used);
}

test "context event processing follows lifecycle" {
    const testing = @import("std").testing;
    var ctx: Context = .{};
    const events = [_]input_events.Event{.{ .pointer_button = .{ .button = .primary, .down = true } }};
    try testing.expectError(error.InvalidFrameState, ctx.processEvents(&events));
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } });
    try ctx.processEvents(&events);
    try testing.expect(ctx.input_processor.snapshot.primary_pressed);
    try ctx.endFrame();
    try testing.expectError(error.InvalidFrameState, ctx.processEvents(&events));
    try ctx.releaseFrame();
}

test "context IDs are frame-scoped and require balanced pushes" {
    const testing = @import("std").testing;
    var ctx: Context = .{};
    const frame: FrameInput = .{ .delta_seconds = 0.016, .display_size = .{ .x = 640, .y = 480 } };
    try testing.expectError(error.InvalidFrameState, ctx.widgetId("button"));
    try ctx.beginFrame(frame);
    const root_id = try ctx.widgetId("button");
    try ctx.pushId("window");
    try testing.expect(root_id != try ctx.widgetId("button"));
    try testing.expectError(error.UnbalancedScopes, ctx.endFrame());
    try testing.expectEqual(FrameState.building, ctx.state);
    try ctx.popId();
    try ctx.endFrame();
    try ctx.releaseFrame();
    try ctx.beginFrame(frame);
    try testing.expectEqual(root_id, try ctx.widgetId("button"));
}

test "widget state survives frames" {
    const testing = @import("std").testing;
    var storage: [8]widget_state.Entry = undefined;
    var ctx: Context = .{};
    try ctx.setStateStorage(&storage);
    const frame: FrameInput = .{ .delta_seconds = 0.016, .display_size = .{ .x = 640, .y = 480 } };
    try ctx.beginFrame(frame);
    const id = try ctx.widgetId("counter");
    (try ctx.widgetState(id)).value = 42;
    try ctx.endFrame();
    try ctx.releaseFrame();
    try ctx.beginFrame(frame);
    try testing.expectEqual(@as(u64, 42), (try ctx.widgetState(id)).value);
}

test "context draw data is ready-only and resets on next frame" {
    const testing = std.testing;
    var vertices: [4]draw.Vertex = undefined;
    var indices: [6]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    const frame: FrameInput = .{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } };
    try ctx.beginFrame(frame);
    const clip_rect: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try ctx.drawRect(0, 0, 10, 10, 0xffffffff, 0, clip_rect);
    try testing.expectError(error.InvalidFrameState, ctx.drawData());
    try ctx.endFrame();
    const data = try ctx.drawData();
    try testing.expectEqual(@as(usize, 6), data.indexSlice().len);
    try ctx.releaseFrame();
    try testing.expectError(error.InvalidFrameState, ctx.drawData());
    try ctx.beginFrame(frame);
    try testing.expectEqual(@as(usize, 0), ctx.geometry.?.index_count);
}

test "context clip stack and draw commands" {
    const testing = std.testing;
    var vertices: [8]draw.Vertex = undefined;
    var indices: [12]u32 = undefined;
    var commands: [2]draw.Command = undefined;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } });
    try ctx.pushClip(.{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 });
    try ctx.pushClip(.{ .min_x = 10, .min_y = 10, .max_x = 40, .max_y = 40 });
    try ctx.drawRectClipped(10, 10, 20, 20, 0xffffffff, 0);
    try testing.expectError(error.UnbalancedClips, ctx.endFrame());
    try testing.expectEqual(FrameState.building, ctx.state);
    try ctx.popClip();
    try ctx.drawRectClipped(20, 20, 30, 30, 0xffffffff, 0);
    try ctx.popClip();
    try ctx.endFrame();
    const data = try ctx.drawData();
    try testing.expectEqual(@as(usize, 2), data.command_count);
    try testing.expectEqual(@as(f32, 40), data.commands[0].clip.max_x);
    try testing.expectEqual(@as(f32, 100), data.commands[1].clip.max_x);
    try ctx.releaseFrame();
}
