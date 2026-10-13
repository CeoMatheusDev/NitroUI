//! NitroUI: engine-first immediate-mode UI contracts.
//! Initial milestone: frame lifecycle and input/display boundary only.

const std = @import("std");
pub const memory = @import("memory.zig");
pub const input_events = @import("input.zig");
pub const ids = @import("ids.zig");
pub const widget_state = @import("state.zig");
pub const draw = @import("draw.zig");
pub const clip = @import("clip.zig");
pub const layout = @import("layout.zig");
pub const interaction = @import("interaction.zig");
pub const style = @import("style.zig");

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
    /// Opt in to synchronizing the two mouse fields with the event processor.
    /// When false, processEvents() remains the sole mouse input source.
    use_mouse_snapshot: bool = false,
};

pub const Error = error{
    InvalidFrameState,
    InvalidDeltaTime,
    InvalidDisplaySize,
    FrameCounterOverflow,
    OverlappingBuffers,
    AddressOverflow,
    MissingGeometry,
    /// Required caller-owned storage (state table or arena) was never attached.
    /// Distinct from OutOfCapacity, which means attached storage is full.
    MissingStorage,
    InvalidMousePosition,
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
    layout_stack: layout.Stack = .{},
    interaction_state: interaction.State = .{},
    visual_style: style.Style = style.Style.dark(),

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
        if (self.interaction_state.visited_ids) |tracked| {
            const bytes = std.mem.sliceAsBytes(tracked);
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

    pub fn drawRoundedRect(self: *Context, x0: f32, y0: f32, x1: f32, y1: f32, radii: draw.CornerRadii, segments_per_corner: u8, color: u32, texture: u64, clip_rect: draw.ClipRect) (Error || draw.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.geometry) |*buffer| return buffer.addRoundedRect(x0, y0, x1, y1, radii, segments_per_corner, color, texture, clip_rect);
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

    pub fn drawRoundedRectClipped(self: *Context, x0: f32, y0: f32, x1: f32, y1: f32, radii: draw.CornerRadii, segments_per_corner: u8, color: u32, texture: u64) (Error || draw.Error || clip.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        const region = self.clip_stack.current() orelse return error.InvalidClip;
        try self.drawRoundedRect(x0, y0, x1, y1, radii, segments_per_corner, color, texture, region);
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

    /// Borrowed immutable slices containing only the emitted geometry.
    /// Available after endFrame() and invalidated by releaseFrame().
    /// No copying or allocation occurs. The engine must not mutate the
    /// underlying storage while it is consuming this view.
    /// Counters are revalidated here so corrupted public counts return an
    /// error instead of trapping on an out-of-bounds slice.
    pub fn drawDataView(self: *const Context) (Error || draw.Error)!draw.View {
        if (self.state != .ready) return error.InvalidFrameState;
        const geometry = self.geometry orelse return error.MissingGeometry;
        if (geometry.vertex_count > geometry.vertices.len or
            geometry.index_count > geometry.indices.len or
            geometry.command_count > geometry.commands.len) return error.OutOfCapacity;
        if (geometry.vertex_count > std.math.maxInt(u32) or
            geometry.index_count > std.math.maxInt(u32)) return error.IndexOverflow;
        if (geometry.command_count > 0) {
            var expected: u64 = 0;
            for (geometry.commands[0..geometry.command_count]) |command| {
                if (@as(u64, command.first_index) != expected) return error.InvalidGeometry;
                const end = @as(u64, command.first_index) + @as(u64, command.index_count);
                if (end > @as(u64, @intCast(geometry.index_count))) return error.InvalidGeometry;
                expected = end;
            }
            if (expected != @as(u64, @intCast(geometry.index_count))) return error.InvalidGeometry;
        } else if (geometry.index_count != 0) {
            return error.InvalidGeometry;
        }
        return geometry.view();
    }

    /// Legacy mutable buffer view; prefer drawDataView() for renderer access.
    /// Available only after endFrame and before releaseFrame.
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
        if (self.interaction_state.visited_ids) |tracked| try ensureDisjoint(bytes, std.mem.sliceAsBytes(tracked));
        self.states = try widget_state.Table.init(storage);
    }

    /// Returns a mutable entry whose value survives frame transitions.
    /// Requires state storage attached via setStateStorage; a full table
    /// still reports OutOfCapacity from the table itself.
    pub fn widgetState(self: *Context, id: ids.Id) (Error || widget_state.Error)!*widget_state.Entry {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.states) |*table| return table.getOrPut(id, self.frame_number);
        return error.MissingStorage;
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
        if (self.interaction_state.visited_ids) |tracked| {
            const bytes = std.mem.sliceAsBytes(tracked);
            try ensureDisjoint(scratch_storage, bytes);
            try ensureDisjoint(render_storage, bytes);
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
        if (self.interaction_state.visited_ids) |tracked| try ensureDisjoint(storage, std.mem.sliceAsBytes(tracked));
        self.persistent = memory.ByteArena.init(storage);
    }

    /// Persistent bytes survive frames, until the buffer is replaced or destroyed.
    /// Reservations are only permitted during the building phase.
    pub fn reservePersistent(self: *Context, count: usize) (Error || memory.Error)![]u8 {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.persistent) |*arena| return arena.reserve(count);
        return error.MissingStorage;
    }

    /// Aligned persistent storage. Padding is charged to the persistent arena.
    pub fn reservePersistentAligned(self: *Context, count: usize, alignment: usize) (Error || memory.Error)![]u8 {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.persistent) |*arena| return arena.reserveAligned(count, alignment);
        return error.MissingStorage;
    }

    /// Aligned scratch storage. Valid until the next beginFrame().
    pub fn reserveScratchAligned(self: *Context, count: usize, alignment: usize) (Error || memory.Error)![]u8 {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.scratch) |*arena| return arena.reserveAligned(count, alignment);
        return error.MissingStorage;
    }

    /// Aligned render storage. Must not be accessed after releaseFrame().
    pub fn reserveRenderAligned(self: *Context, count: usize, alignment: usize) (Error || memory.Error)![]u8 {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.render) |*arena| return arena.reserveAligned(count, alignment);
        return error.MissingStorage;
    }

    /// Frame-temporary bytes, invalidated at the next beginFrame().
    pub fn reserveScratch(self: *Context, count: usize) (Error || memory.Error)![]u8 {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.scratch) |*arena| return arena.reserve(count);
        return error.MissingStorage;
    }

    /// Render bytes remain valid through ready, until releaseFrame().
    pub fn reserveRender(self: *Context, count: usize) (Error || memory.Error)![]u8 {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.render) |*arena| return arena.reserve(count);
        return error.MissingStorage;
    }

    /// Opens a frame: idle -> building. Validates time/display input, resets
    /// scratch/render arenas and geometry counts, then snapshots continuous
    /// mouse state when requested. All rejections leave the context idle.
    pub fn beginFrame(self: *Context, input: FrameInput) Error!void {
        if (self.state != .idle) return error.InvalidFrameState;
        if (!isFinite(input.delta_seconds) or input.delta_seconds < 0)
            return error.InvalidDeltaTime;
        if (!isFinite(input.display_size.x) or !isFinite(input.display_size.y) or
            input.display_size.x <= 0 or input.display_size.y <= 0)
            return error.InvalidDisplaySize;
        if (input.use_mouse_snapshot and (!isFinite(input.mouse_position.x) or !isFinite(input.mouse_position.y)))
            return error.InvalidMousePosition;
        if (self.frame_number == ~@as(u64, 0)) return error.FrameCounterOverflow;
        if (self.geometry) |*buffer| buffer.reset();
        if (self.scratch) |*arena| arena.reset();
        if (self.render) |*arena| arena.reset();
        self.input = input;
        self.input_processor.beginFrame();
        if (input.use_mouse_snapshot) {
            const snapshot = &self.input_processor.snapshot;
            const was_down = (snapshot.buttons_down & 1) != 0;
            snapshot.pointer_x = input.mouse_position.x;
            snapshot.pointer_y = input.mouse_position.y;
            if (input.mouse_primary_down) {
                snapshot.buttons_down |= 1;
                if (!was_down) snapshot.primary_pressed = true;
            } else {
                snapshot.buttons_down &= ~@as(u8, 1);
                if (was_down) snapshot.primary_released = true;
            }
        }
        self.id_stack.reset();
        self.clip_stack.reset();
        self.layout_stack.reset();
        self.interaction_state.beginFrame();
        self.state = .building;
    }

    /// Begin a sequential layout region. All layout operations are building-only.
    pub fn pushLayout(self: *Context, bounds: layout.Rect, spacing: layout.Spacing) (Error || layout.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        try self.layout_stack.push(bounds, spacing);
    }

    pub fn nextLayoutRect(self: *Context, width: ?f32, height: f32) (Error || layout.Error)!layout.Rect {
        if (self.state != .building) return error.InvalidFrameState;
        return self.layout_stack.next(width, height);
    }

    pub fn popLayout(self: *Context) (Error || layout.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        try self.layout_stack.pop();
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

    /// Submit an interactive item after processing input for this frame.
    pub fn interact(self: *Context, id: ids.Id, rect: layout.Rect) (Error || interaction.Error)!interaction.Result {
        if (self.state != .building) return error.InvalidFrameState;
        return self.interaction_state.item(id, rect, self.input_processor.snapshot);
    }

    /// Enable optional per-frame duplicate-ID diagnostics using engine-owned storage.
    /// O(n) lookup per item when enabled; no allocation and no storage when disabled.
    /// Configure while idle. The storage must remain valid until detached.
    /// Rejected when overlapping any other active storage; on failure the
    /// previous tracking configuration is preserved.
    pub fn setInteractionIdStorage(self: *Context, storage: ?[]ids.Id) (Error || interaction.Error)!void {
        if (self.state != .idle) return error.InvalidFrameState;
        if (storage) |tracked| {
            const bytes = std.mem.sliceAsBytes(tracked);
            if (self.scratch) |arena| try ensureDisjoint(bytes, arena.storage);
            if (self.render) |arena| try ensureDisjoint(bytes, arena.storage);
            if (self.persistent) |arena| try ensureDisjoint(bytes, arena.storage);
            if (self.states) |table| {
                const state_bytes = @as([*]const u8, @ptrCast(table.entries.ptr))[0 .. table.entries.len * @sizeOf(widget_state.Entry)];
                try ensureDisjoint(bytes, state_bytes);
            }
            if (self.geometry) |g| try ensureGeometryDisjoint(bytes, g);
        }
        try self.interaction_state.setIdTrackingStorage(storage);
    }

    /// Change the per-context style outside frame construction. No allocation.
    pub fn setStyle(self: *Context, new_style: style.Style) error{ InvalidFrameState, InvalidStyle }!void {
        if (self.state != .idle) return error.InvalidFrameState;
        if (!new_style.valid()) return error.InvalidStyle;
        self.visual_style = new_style;
    }

    // A widget may emit multiple primitives. Restore the logical draw prefix and
    // pointer-capture state if any primitive fails. Previously written tail data
    // remains outside the published counts and will be overwritten on reuse.
    const WidgetCheckpoint = struct {
        geometry: draw.Buffer,
        interaction_state: interaction.State,
        last_command: ?draw.Command,
    };

    fn checkpointWidget(self: *Context) Error!WidgetCheckpoint {
        if (self.state != .building) return error.InvalidFrameState;
        const buffer = self.geometry orelse return error.MissingGeometry;
        return .{
            .geometry = buffer,
            .interaction_state = self.interaction_state,
            .last_command = if (buffer.command_count > 0 and buffer.command_count <= buffer.commands.len)
                buffer.commands[buffer.command_count - 1]
            else
                null,
        };
    }

    fn rollbackWidget(self: *Context, checkpoint: WidgetCheckpoint) void {
        self.interaction_state = checkpoint.interaction_state;
        self.geometry = checkpoint.geometry;
        if (checkpoint.last_command) |command| {
            checkpoint.geometry.commands[checkpoint.geometry.command_count - 1] = command;
        }
    }

    /// Basic button: returns true on primary-button release over its bounds.
    /// Caller provides a stable ID and a valid clip rectangle.
    pub fn button(self: *Context, id: ids.Id, rect: layout.Rect, clip_rect: draw.ClipRect) (Error || interaction.Error || draw.Error)!bool {
        const checkpoint = try self.checkpointWidget();
        errdefer self.rollbackWidget(checkpoint);
        const result = try self.interact(id, rect);
        const color: u32 = if (result.held) self.visual_style.colors.button_active else if (result.hovered) self.visual_style.colors.button_hovered else self.visual_style.colors.button;
        try self.drawRect(rect.x, rect.y, rect.x + rect.width, rect.y + rect.height, color, 0, clip_rect);
        return result.clicked;
    }

    /// Checkbox value is caller-owned. A successful click toggles it once.
    pub fn checkbox(self: *Context, id: ids.Id, rect: layout.Rect, value: *bool, clip_rect: draw.ClipRect) (Error || interaction.Error || draw.Error)!bool {
        const checkpoint = try self.checkpointWidget();
        errdefer self.rollbackWidget(checkpoint);
        const result = try self.interact(id, rect);
        const color: u32 = if (result.hovered) self.visual_style.colors.checkbox_hovered else self.visual_style.colors.checkbox;
        try self.drawRect(rect.x, rect.y, rect.x + rect.width, rect.y + rect.height, color, 0, clip_rect);
        if (value.*) {
            const inset = @min(rect.width, rect.height) * 0.25;
            try self.drawRect(rect.x + inset, rect.y + inset, rect.x + rect.width - inset, rect.y + rect.height - inset, self.visual_style.colors.checkmark, 0, clip_rect);
        }
        if (result.clicked) value.* = !value.*;
        return result.clicked;
    }

    /// Pointer-driven scalar slider. Value is caller-owned and constrained to [min, max].
    /// Returns true when the value changes. No persistent per-widget allocation.
    pub fn sliderFloat(self: *Context, id: ids.Id, rect: layout.Rect, value: *f32, min: f32, max: f32, clip_rect: draw.ClipRect) (Error || interaction.Error || draw.Error)!bool {
        if (!std.math.isFinite(min) or !std.math.isFinite(max) or !(max > min) or
            !std.math.isFinite(max - min) or !std.math.isFinite(value.*) or
            !std.math.isFinite(rect.width) or rect.width <= 0)
            return error.InvalidGeometry;
        const checkpoint = try self.checkpointWidget();
        errdefer self.rollbackWidget(checkpoint);
        const result = try self.interact(id, rect);
        var next = std.math.clamp(value.*, min, max);
        if (result.held or result.pressed or result.clicked) {
            const pointer_x = self.input_processor.snapshot.pointer_x;
            const fraction = std.math.clamp((pointer_x - rect.x) / rect.width, 0.0, 1.0);
            next = min + fraction * (max - min);
        }
        const fraction = std.math.clamp((next - min) / (max - min), 0.0, 1.0);
        try self.drawRect(rect.x, rect.y, rect.x + rect.width, rect.y + rect.height, self.visual_style.colors.slider_track, 0, clip_rect);
        if (fraction > 0) {
            try self.drawRect(rect.x, rect.y, rect.x + rect.width * fraction, rect.y + rect.height, self.visual_style.colors.slider_fill, 0, clip_rect);
        }
        const changed = next != value.*;
        value.* = next;
        return changed;
    }

    /// Closes a frame: building -> ready. Requires balanced ID/clip/layout
    /// stacks; any failure keeps the building state and reports the cause.
    /// On success the frame number advances and draw data becomes available.
    pub fn endFrame(self: *Context) (Error || ids.Error || clip.Error || layout.Error || interaction.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        try self.id_stack.validateBalanced();
        try self.clip_stack.validateBalanced();
        try self.layout_stack.validateBalanced();
        try self.interaction_state.endFrame(self.input_processor.snapshot);
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

test "context layout requires frame and balanced regions" {
    const t = std.testing;
    var ctx: Context = .{};
    try t.expectError(error.InvalidFrameState, ctx.nextLayoutRect(null, 5));
    const frame: FrameInput = .{ .delta_seconds = 0.016, .display_size = .{ .x = 800, .y = 600 } };
    try ctx.beginFrame(frame);
    try ctx.pushLayout(.{ .x = 2, .y = 4, .width = 100, .height = 100 }, .{ .x = 2, .y = 4 });
    const rect = try ctx.nextLayoutRect(null, 10);
    try t.expectEqual(@as(f32, 4), rect.x);
    try t.expectEqual(@as(f32, 96), rect.width);
    try t.expectError(error.UnbalancedStack, ctx.endFrame());
    try ctx.popLayout();
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "context interaction captures primary click across frames" {
    const t = std.testing;
    var ctx: Context = .{};
    const frame: FrameInput = .{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } };
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 30, .height = 20 };
    try ctx.beginFrame(frame);
    try ctx.processEvents(&.{ .{ .pointer_move = .{ .x = 5, .y = 5 } }, .{ .pointer_button = .{ .button = .primary, .down = true } } });
    const id = try ctx.widgetId("button");
    try t.expect((try ctx.interact(id, rect)).pressed);
    try ctx.endFrame();
    try ctx.releaseFrame();
    try ctx.beginFrame(frame);
    try ctx.processEvents(&.{.{ .pointer_button = .{ .button = .primary, .down = false } }});
    try t.expect((try ctx.interact(try ctx.widgetId("button"), rect)).clicked);
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "stage20 basic widgets integrate interaction and geometry" {
    const t = std.testing;
    var vertices: [64]draw.Vertex = undefined;
    var indices: [96]u32 = undefined;
    var commands: [16]draw.Command = undefined;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    const frame: FrameInput = .{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } };
    const bounds: layout.Rect = .{ .x = 0, .y = 0, .width = 50, .height = 20 };
    const region: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    var checked = false;
    var scalar: f32 = 0;
    try ctx.beginFrame(frame);
    try ctx.processEvents(&.{ .{ .pointer_move = .{ .x = 10, .y = 10 } }, .{ .pointer_button = .{ .button = .primary, .down = true } }, .{ .pointer_button = .{ .button = .primary, .down = false } } });
    try t.expect(try ctx.button(1, bounds, region));
    try t.expect(!(try ctx.checkbox(2, bounds, &checked, region)));
    try t.expect(!checked);
    try ctx.endFrame();
    try t.expect((try ctx.drawData()).vertex_count > 0);
    try ctx.releaseFrame();

    try ctx.beginFrame(frame);
    try ctx.processEvents(&.{ .{ .pointer_move = .{ .x = 25, .y = 10 } }, .{ .pointer_button = .{ .button = .primary, .down = true } } });
    try t.expect(try ctx.sliderFloat(3, bounds, &scalar, 0, 10, region));
    try t.expectApproxEqAbs(@as(f32, 5), scalar, 0.001);
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "stage21 style changes are idle-only and transactional" {
    const testing = std.testing;
    var ctx: Context = .{};
    const old_color = ctx.visual_style.colors.button;
    var invalid = style.Style.light();
    invalid.frame_padding_x = -1;
    try testing.expectError(error.InvalidStyle, ctx.setStyle(invalid));
    try testing.expectEqual(old_color, ctx.visual_style.colors.button);
    try ctx.setStyle(style.Style.light());
    try testing.expectEqual(style.Style.light().colors.button, ctx.visual_style.colors.button);
    try ctx.beginFrame(.{ .delta_seconds = 1.0 / 60.0, .display_size = .{ .x = 640, .y = 480 } });
    try testing.expectError(error.InvalidFrameState, ctx.setStyle(style.Style.dark()));
    try ctx.endFrame();
    try ctx.releaseFrame();
    try testing.expectEqual(style.Style.light().colors.button, ctx.visual_style.colors.button);
}

test "stage22 headless multi-frame input layout widgets and draw data" {
    const t = std.testing;
    var vertices: [128]draw.Vertex = undefined;
    var indices: [192]u32 = undefined;
    var commands: [32]draw.Command = undefined;
    var scratch: [128]u8 = undefined;
    var render_bytes: [128]u8 = undefined;
    var ctx: Context = .{};
    try ctx.setBuffers(&scratch, &render_bytes);
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    try ctx.setStyle(style.Style.light());
    const frame: FrameInput = .{ .delta_seconds = 1.0 / 60.0, .display_size = .{ .x = 320, .y = 240 } };
    const region: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 320, .max_y = 240 };
    const bounds: layout.Rect = .{ .x = 10, .y = 10, .width = 120, .height = 120 };
    var checked = false;
    var scalar: f32 = 0;
    const events = [_][]const input_events.Event{
        &.{ .{ .pointer_move = .{ .x = 20, .y = 20 } }, .{ .pointer_button = .{ .button = .primary, .down = true } } },
        &.{.{ .pointer_button = .{ .button = .primary, .down = false } }},
        &.{ .{ .pointer_move = .{ .x = 20, .y = 48 } }, .{ .pointer_button = .{ .button = .primary, .down = true } }, .{ .pointer_button = .{ .button = .primary, .down = false } } },
        &.{ .{ .pointer_move = .{ .x = 70, .y = 75 } }, .{ .pointer_button = .{ .button = .primary, .down = true } } },
        &.{.{ .pointer_button = .{ .button = .primary, .down = false } }},
    };
    for (events, 0..) |batch, frame_index| {
        try ctx.beginFrame(frame);
        try ctx.processEvents(batch);
        try ctx.pushLayout(bounds, .{ .x = 0, .y = 4 });
        const button_rect = try ctx.nextLayoutRect(null, 24);
        const checkbox_rect = try ctx.nextLayoutRect(null, 20);
        const slider_rect = try ctx.nextLayoutRect(null, 20);
        try ctx.pushClip(region);
        const button_clicked = try ctx.button(try ctx.widgetId("button"), button_rect, region);
        const checkbox_changed = try ctx.checkbox(try ctx.widgetId("checkbox"), checkbox_rect, &checked, region);
        const slider_changed = try ctx.sliderFloat(try ctx.widgetId("slider"), slider_rect, &scalar, 0, 1, region);
        try ctx.popClip();
        try ctx.popLayout();
        if (frame_index == 1) try t.expect(button_clicked) else try t.expect(!button_clicked);
        if (frame_index == 2) try t.expect(checkbox_changed) else try t.expect(!checkbox_changed);
        if (frame_index == 3) try t.expect(slider_changed);
        try ctx.endFrame();
        const data = try ctx.drawData();
        try t.expect(data.vertex_count > 0);
        try t.expect(data.index_count > 0);
        try t.expect(data.command_count > 0);
        for (data.indexSlice()) |index| try t.expect(index < data.vertex_count);
        var expected_first: usize = 0;
        for (data.commandSlice()) |command| {
            try t.expectEqual(expected_first, @as(usize, command.first_index));
            expected_first += command.index_count;
            try t.expect(expected_first <= data.index_count);
            try t.expectEqual(region.min_x, command.clip.min_x);
            try t.expectEqual(region.max_x, command.clip.max_x);
        }
        try t.expectEqual(data.index_count, expected_first);
        try t.expectError(error.InvalidFrameState, ctx.beginFrame(frame));
        try ctx.releaseFrame();
        try t.expectEqual(@as(usize, 0), ctx.scratch.?.used);
        try t.expectEqual(@as(usize, 0), ctx.render.?.used);
    }
    try t.expect(checked);
    try t.expectApproxEqAbs(@as(f32, 0.5), scalar, 0.001);
    try t.expectEqual(@as(u64, events.len), ctx.frame_number);
    try t.expectEqual(style.Style.light().colors.button, ctx.visual_style.colors.button);
}

test "stage22 headless geometry exhaustion returns error without corrupting buffer" {
    const t = std.testing;
    var vertices: [4]draw.Vertex = undefined;
    var indices: [6]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } });
    const clip_rect: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try ctx.drawRect(0, 0, 10, 10, 0xffffffff, 0, clip_rect);
    try t.expectError(error.OutOfCapacity, ctx.drawRect(10, 0, 20, 10, 0xffffffff, 0, clip_rect));
    try ctx.endFrame();
    const data = try ctx.drawData();
    try t.expectEqual(@as(usize, 4), data.vertex_count);
    try t.expectEqual(@as(usize, 6), data.index_count);
    try t.expectEqual(@as(usize, 1), data.command_count);
    try ctx.releaseFrame();
}

test "stage24 widget failure rolls back interaction and geometry" {
    const t = std.testing;
    var vertices: [8]draw.Vertex = undefined;
    var indices: [12]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    const frame: FrameInput = .{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } };
    const bounds: layout.Rect = .{ .x = 0, .y = 0, .width = 50, .height = 20 };
    const region: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try ctx.beginFrame(frame);
    try ctx.processEvents(&.{ .{ .pointer_move = .{ .x = 10, .y = 10 } }, .{ .pointer_button = .{ .button = .primary, .down = true } } });
    try ctx.drawRect(0, 0, 10, 10, 0xffffffff, 0, region);
    const prior_command = ctx.geometry.?.commands[0];
    const prior_interaction = ctx.interaction_state;
    var checked = true;
    try t.expectError(error.OutOfCapacity, ctx.checkbox(1, bounds, &checked, region));
    try t.expect(checked);
    try t.expectEqual(@as(usize, 4), ctx.geometry.?.vertex_count);
    try t.expectEqual(@as(usize, 6), ctx.geometry.?.index_count);
    try t.expectEqual(@as(usize, 1), ctx.geometry.?.command_count);
    try t.expectEqualDeep(prior_command, ctx.geometry.?.commands[0]);
    try t.expectEqualDeep(prior_interaction, ctx.interaction_state);
    // The failed checkbox rolled back to one rectangle. Fill the remaining
    // capacity before testing that a button also fails without side effects.
    try ctx.drawRect(10, 0, 20, 10, 0xffffffff, 0, region);
    const full_command = ctx.geometry.?.commands[0];
    try t.expectError(error.OutOfCapacity, ctx.button(2, bounds, region));
    try t.expectEqual(@as(usize, 8), ctx.geometry.?.vertex_count);
    try t.expectEqual(@as(usize, 12), ctx.geometry.?.index_count);
    try t.expectEqual(@as(usize, 1), ctx.geometry.?.command_count);
    try t.expectEqualDeep(full_command, ctx.geometry.?.commands[0]);
    try t.expectEqualDeep(prior_interaction, ctx.interaction_state);
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "stage24 slider failure preserves caller value and capture" {
    const t = std.testing;
    var vertices: [0]draw.Vertex = .{};
    var indices: [0]u32 = .{};
    var commands: [0]draw.Command = .{};
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } });
    try ctx.processEvents(&.{ .{ .pointer_move = .{ .x = 25, .y = 10 } }, .{ .pointer_button = .{ .button = .primary, .down = true } } });
    const before = ctx.interaction_state;
    var value: f32 = 0.25;
    try t.expectError(error.OutOfCapacity, ctx.sliderFloat(3, .{ .x = 0, .y = 0, .width = 50, .height = 20 }, &value, 0, 1, .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 }));
    try t.expectEqual(@as(f32, 0.25), value);
    try t.expectEqualDeep(before, ctx.interaction_state);
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "optional frame mouse snapshot generates transitions across frames" {
    const t = std.testing;
    var ctx: Context = .{};
    const frame: FrameInput = .{
        .delta_seconds = 0.016,
        .display_size = .{ .x = 100, .y = 100 },
        .mouse_position = .{ .x = 12, .y = 34 },
        .mouse_primary_down = true,
        .use_mouse_snapshot = true,
    };
    try ctx.beginFrame(frame);
    try t.expectEqual(@as(f32, 12), ctx.input_processor.snapshot.pointer_x);
    try t.expectEqual(@as(f32, 34), ctx.input_processor.snapshot.pointer_y);
    try t.expect(ctx.input_processor.snapshot.primary_pressed);
    try ctx.endFrame();
    try ctx.releaseFrame();

    try ctx.beginFrame(frame);
    try t.expect(!ctx.input_processor.snapshot.primary_pressed);
    try t.expect((ctx.input_processor.snapshot.buttons_down & 1) != 0);
    try ctx.endFrame();
    try ctx.releaseFrame();

    var released = frame;
    released.mouse_primary_down = false;
    try ctx.beginFrame(released);
    try t.expect(ctx.input_processor.snapshot.primary_released);
    try t.expect((ctx.input_processor.snapshot.buttons_down & 1) == 0);
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "mouse snapshot is opt-in and invalid coordinates preserve idle state" {
    const t = std.testing;
    var ctx: Context = .{};
    const frame: FrameInput = .{
        .delta_seconds = 0.016,
        .display_size = .{ .x = 100, .y = 100 },
        .mouse_position = .{ .x = 10, .y = 20 },
        .mouse_primary_down = true,
    };
    try ctx.beginFrame(frame);
    try t.expect(!ctx.input_processor.snapshot.primary_pressed);
    try t.expectEqual(@as(f32, 0), ctx.input_processor.snapshot.pointer_x);
    try ctx.endFrame();
    try ctx.releaseFrame();

    var invalid = frame;
    invalid.use_mouse_snapshot = true;
    invalid.mouse_position.x = std.math.inf(f32);
    try t.expectError(error.InvalidMousePosition, ctx.beginFrame(invalid));
    try t.expectEqual(FrameState.idle, ctx.state);
}

test "event batches override opt-in frame mouse state" {
    const t = std.testing;
    var ctx: Context = .{};
    try ctx.beginFrame(.{
        .delta_seconds = 0.016,
        .display_size = .{ .x = 100, .y = 100 },
        .mouse_position = .{ .x = 5, .y = 6 },
        .mouse_primary_down = true,
        .use_mouse_snapshot = true,
    });
    try ctx.processEvents(&.{
        .{ .pointer_move = .{ .x = 25, .y = 30 } },
        .{ .pointer_button = .{ .button = .primary, .down = false } },
    });
    try t.expectEqual(@as(f32, 25), ctx.input_processor.snapshot.pointer_x);
    try t.expect(ctx.input_processor.snapshot.primary_pressed);
    try t.expect(ctx.input_processor.snapshot.primary_released);
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "drawDataView exposes used read-only slices only while ready" {
    const t = std.testing;
    var vertices: [8]draw.Vertex = undefined;
    var indices: [12]u32 = undefined;
    var commands: [2]draw.Command = undefined;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    try t.expectError(error.InvalidFrameState, ctx.drawDataView());
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } });
    try t.expectError(error.InvalidFrameState, ctx.drawDataView());
    try ctx.drawRect(0, 0, 10, 10, 0xffffffff, 0, .{
        .min_x = 0,
        .min_y = 0,
        .max_x = 100,
        .max_y = 100,
    });
    try ctx.endFrame();
    const view = try ctx.drawDataView();
    try t.expectEqual(@as(usize, 4), view.vertices.len);
    try t.expectEqual(@as(usize, 6), view.indices.len);
    try t.expectEqual(@as(usize, 1), view.commands.len);
    try t.expectEqual(@as(u32, 0), view.indices[0]);
    try t.expectEqual(@as(u32, 6), view.commands[0].index_count);
    // The view borrows the original engine-owned buffers (no copy).
    try t.expectEqual(@intFromPtr(vertices[0..].ptr), @intFromPtr(view.vertices.ptr));
    try t.expectEqual(@intFromPtr(indices[0..].ptr), @intFromPtr(view.indices.ptr));
    try t.expectEqual(@intFromPtr(commands[0..].ptr), @intFromPtr(view.commands.ptr));
    try ctx.releaseFrame();
    try t.expectError(error.InvalidFrameState, ctx.drawDataView());
}

test "drawDataView requires configured geometry" {
    const t = std.testing;
    var ctx: Context = .{};
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } });
    try ctx.endFrame();
    try t.expectError(error.MissingGeometry, ctx.drawDataView());
    try ctx.releaseFrame();
}

test "stage24_5 context duplicate IDs, scope IDs and rollback" {
    const t = std.testing;
    var ctx: Context = .{};
    var visited: [3]ids.Id = undefined;
    var vertices: [4]draw.Vertex = undefined;
    var indices: [6]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    try ctx.setInteractionIdStorage(&visited);
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    const frame: FrameInput = .{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } };
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const away: layout.Rect = .{ .x = 50, .y = 50, .width = 10, .height = 10 };
    const clip_rect: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try ctx.beginFrame(frame);
    _ = try ctx.interact(42, away);
    try t.expectError(error.DuplicateId, ctx.interact(42, away));
    var checked = true;
    try t.expectError(error.OutOfCapacity, ctx.checkbox(100, rect, &checked, clip_rect));
    // Failed widget must not consume diagnostic capacity.
    try t.expectEqual(@as(usize, 1), ctx.interaction_state.visited_count);
    _ = try ctx.interact(100, away);
    try ctx.endFrame();
    try ctx.releaseFrame();
    try ctx.beginFrame(frame);
    _ = try ctx.interact(42, away);
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "stage24_6 failed widget can retry same ID after restoring geometry capacity" {
    const t = std.testing;
    var vertices: [8]draw.Vertex = undefined;
    var indices: [12]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    var visited: [2]ids.Id = undefined;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    try ctx.setInteractionIdStorage(&visited);
    const frame: FrameInput = .{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } };
    const region: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 20, .height = 20 };
    try ctx.beginFrame(frame);
    try ctx.drawRect(40, 40, 50, 50, 0xffffffff, 0, region);
    var checked = true;
    try t.expectError(error.OutOfCapacity, ctx.checkbox(7, rect, &checked, region));
    try t.expectEqual(@as(usize, 0), ctx.interaction_state.visited_count);
    try t.expectEqual(@as(usize, 4), ctx.geometry.?.vertex_count);
    // A failed widget may be retried with the same ID; one rectangle still fits.
    try t.expect(!(try ctx.button(7, rect, region)));
    try t.expectEqual(@as(usize, 1), ctx.interaction_state.visited_count);
    try t.expectError(error.DuplicateId, ctx.button(7, rect, region));
    try ctx.endFrame();
    const view = try ctx.drawDataView();
    try t.expectEqual(@as(usize, 8), view.vertices.len);
    try t.expectEqual(@as(usize, 12), view.indices.len);
    try t.expectEqual(@as(usize, 1), view.commands.len);
    try ctx.releaseFrame();
}

test "stage24_6 ready frame preserves view and rejects mutation through context" {
    const t = std.testing;
    var vertices: [4]draw.Vertex = undefined;
    var indices: [6]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    const frame: FrameInput = .{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } };
    const region: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try ctx.beginFrame(frame);
    try ctx.drawRect(0, 0, 10, 10, 0xffffffff, 0, region);
    try ctx.endFrame();
    const view = try ctx.drawDataView();
    const first_vertex = view.vertices[0];
    const first_command = view.commands[0];
    try t.expectError(error.InvalidFrameState, ctx.beginFrame(frame));
    try t.expectError(error.InvalidFrameState, ctx.drawRect(0, 0, 10, 10, 0xffffffff, 0, region));
    try t.expectError(error.InvalidFrameState, ctx.setInteractionIdStorage(null));
    try t.expectEqualDeep(first_vertex, view.vertices[0]);
    try t.expectEqualDeep(first_command, view.commands[0]);
    try ctx.releaseFrame();
    try t.expectError(error.InvalidFrameState, ctx.drawDataView());
    try ctx.beginFrame(frame);
    try ctx.endFrame();
    const empty = try ctx.drawDataView();
    try t.expectEqual(@as(usize, 0), empty.vertices.len);
    try t.expectEqual(@as(usize, 0), empty.indices.len);
    try t.expectEqual(@as(usize, 0), empty.commands.len);
    try ctx.releaseFrame();
}

test "stage24_8 id tracking storage rejects overlap transactionally" {
    const t = std.testing;
    var id_backing: [16]ids.Id = undefined;
    var indices: [6]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    const v_ptr: [*]draw.Vertex = @ptrCast(@alignCast(id_backing[0..].ptr));
    const aliased_vertices = v_ptr[0..4];
    var ctx: Context = .{};
    try ctx.setGeometryStorage(aliased_vertices, &indices, &commands);
    try t.expectError(error.OverlappingBuffers, ctx.setInteractionIdStorage(id_backing[0..2]));
    try t.expect(ctx.interaction_state.visited_ids == null);
    var visited: [2]ids.Id = undefined;
    try ctx.setInteractionIdStorage(&visited);
    var ctx2: Context = .{};
    try ctx2.setInteractionIdStorage(id_backing[0..2]);
    try t.expectError(error.OverlappingBuffers, ctx2.setGeometryStorage(aliased_vertices, &indices, &commands));
    try t.expect(ctx2.geometry == null);
    // Detach and reattach disjoint storage succeeds.
    try ctx.setInteractionIdStorage(null);
    try t.expect(ctx.interaction_state.visited_ids == null);
    try ctx.setInteractionIdStorage(&visited);
    try t.expectEqual(@intFromPtr(visited[0..].ptr), @intFromPtr(ctx.interaction_state.visited_ids.?.ptr));
}

test "stage24_8 id tracking overlap covers arenas and state storage" {
    const t = std.testing;
    var id_backing: [8]ids.Id = undefined;
    var render: [64]u8 = undefined;
    var ctx: Context = .{};
    try ctx.setInteractionIdStorage(id_backing[0..2]);
    try t.expectError(error.OverlappingBuffers, ctx.setBuffers(std.mem.sliceAsBytes(id_backing[0..]), &render));
    try t.expect(ctx.scratch == null);
    try t.expectError(error.OverlappingBuffers, ctx.setPersistentBuffer(std.mem.sliceAsBytes(id_backing[0..])));
    try t.expect(ctx.persistent == null);

    var scratch: [64]u8 align(8) = undefined;
    var render2: [64]u8 = undefined;
    var ctx2: Context = .{};
    try ctx2.setBuffers(&scratch, &render2);
    const tracked_ptr: [*]ids.Id = @ptrCast(@alignCast(scratch[0..].ptr));
    try t.expectError(error.OverlappingBuffers, ctx2.setInteractionIdStorage(tracked_ptr[0..4]));
    try t.expect(ctx2.interaction_state.visited_ids == null);

    var entries: [4]widget_state.Entry = undefined;
    var ctx3: Context = .{};
    try ctx3.setStateStorage(&entries);
    const state_ids: [*]ids.Id = @ptrCast(entries[0..].ptr);
    try t.expectError(error.OverlappingBuffers, ctx3.setInteractionIdStorage(state_ids[0..4]));
    try t.expect(ctx3.interaction_state.visited_ids == null);

    var visited: [4]ids.Id = undefined;
    var ctx4: Context = .{};
    try ctx4.setInteractionIdStorage(&visited);
    var other_render: [64]u8 = undefined;
    try t.expectError(error.OverlappingBuffers, ctx4.setBuffers(std.mem.sliceAsBytes(visited[0..]), &other_render));
    try t.expectError(error.OverlappingBuffers, ctx4.setPersistentBuffer(std.mem.sliceAsBytes(visited[0..])));
    try t.expect(ctx4.persistent == null);
}

test "stage24_8 drawDataView rejects corrupted counters without trapping" {
    const t = std.testing;
    var vertices: [4]draw.Vertex = undefined;
    var indices: [6]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    const frame: FrameInput = .{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } };
    const region: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try ctx.beginFrame(frame);
    try ctx.drawRect(0, 0, 10, 10, 0xffffffff, 0, region);
    try ctx.endFrame();
    _ = try ctx.drawDataView();
    ctx.geometry.?.vertex_count = 5;
    try t.expectError(error.OutOfCapacity, ctx.drawDataView());
    try t.expectEqual(FrameState.ready, ctx.state);
    ctx.geometry.?.vertex_count = 4;
    ctx.geometry.?.commands[0].index_count = 7;
    try t.expectError(error.InvalidGeometry, ctx.drawDataView());
    ctx.geometry.?.commands[0].index_count = 6;
    _ = try ctx.drawDataView();
    try ctx.releaseFrame();
    try ctx.beginFrame(frame);
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.vertex_count);
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "stage24_14 post-warm-up frames reuse buffers without growth" {
    const t = std.testing;
    var vertices: [32]draw.Vertex = undefined;
    var indices: [48]u32 = undefined;
    var commands: [4]draw.Command = undefined;
    var scratch: [256]u8 = undefined;
    var render_bytes: [256]u8 = undefined;
    var persistent_bytes: [64]u8 = undefined;
    var entries: [8]widget_state.Entry = undefined;
    var visited: [8]ids.Id = undefined;
    var ctx: Context = .{};
    try ctx.setBuffers(&scratch, &render_bytes);
    try ctx.setPersistentBuffer(&persistent_bytes);
    try ctx.setStateStorage(&entries);
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    try ctx.setInteractionIdStorage(&visited);
    const frame: FrameInput = .{ .delta_seconds = 1.0 / 60.0, .display_size = .{ .x = 320, .y = 240 } };
    const region: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 320, .max_y = 240 };
    const bounds: layout.Rect = .{ .x = 10, .y = 10, .width = 200, .height = 200 };
    var checked = false;
    var scalar: f32 = 0.5;
    var checksum: u64 = 0;
    var scratch_mark: usize = 0;
    var render_mark: usize = 0;
    var state_mark: usize = 0;
    for (0..40) |n| {
        try ctx.beginFrame(frame);
        try ctx.processEvents(&.{.{ .pointer_move = .{ .x = 20, .y = 20 } }});
        if (n == 0) {
            // All persistent claims happen during warm-up; none afterwards.
            const stored = try ctx.reservePersistent(32);
            stored[0] = 0xAB;
            (try ctx.widgetState(9000)).value = 1234;
        }
        _ = try ctx.reserveScratch(16);
        _ = try ctx.reserveRender(16);
        try ctx.pushLayout(bounds, .{ .x = 0, .y = 4 });
        const br = try ctx.nextLayoutRect(null, 24);
        const cr = try ctx.nextLayoutRect(null, 20);
        const sr = try ctx.nextLayoutRect(null, 20);
        _ = try ctx.button(try ctx.widgetId("button"), br, region);
        _ = try ctx.checkbox(try ctx.widgetId("checkbox"), cr, &checked, region);
        _ = try ctx.sliderFloat(try ctx.widgetId("slider"), sr, &scalar, 0, 1, region);
        _ = try ctx.widgetState(9000);
        try ctx.popLayout();
        try ctx.endFrame();
        const view = try ctx.drawDataView();
        checksum +%= @as(u64, @intCast(view.vertices.len));
        checksum +%= @as(u64, @intCast(view.indices.len));
        checksum +%= @as(u64, @intCast(view.commands.len));
        try ctx.releaseFrame();
        if (n == 2) {
            scratch_mark = ctx.scratch.?.high_watermark;
            render_mark = ctx.render.?.high_watermark;
            state_mark = ctx.states.?.count;
        } else if (n > 2) {
            // Steady state: identical output, no capacity growth, no new states.
            try t.expectEqual(scratch_mark, ctx.scratch.?.high_watermark);
            try t.expectEqual(render_mark, ctx.render.?.high_watermark);
            try t.expectEqual(@as(usize, 32), ctx.persistent.?.high_watermark);
            try t.expectEqual(state_mark, ctx.states.?.count);
            // Each frame claims exactly its 16 transient bytes per arena;
            // cursors reset at the next beginFrame, watermarks never grow.
            try t.expectEqual(@as(usize, 16), ctx.scratch.?.used);
            try t.expectEqual(@as(usize, 16), ctx.render.?.used);
        }
    }
    // 40 identical frames: button(4v/6i) + checkbox(4v/6i, unchecked) +
    // slider(8v/12i at 0.5) + 1 batched command = 16v/24i/1c per frame.
    try t.expectEqual(@as(u64, 40 * (16 + 24 + 1)), checksum);
    try t.expectEqual(@as(usize, 1), state_mark);
    try t.expect(!checked);
    try t.expectEqual(@as(f32, 0.5), scalar);
    try t.expectEqual(@as(u8, 0xAB), persistent_bytes[0]);
}

test "stage24_16 unconfigured storage reports MissingStorage, full reports OutOfCapacity" {
    const t = std.testing;
    var ctx: Context = .{};
    const frame: FrameInput = .{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } };
    try ctx.beginFrame(frame);
    try t.expectError(error.MissingStorage, ctx.widgetState(1));
    try t.expectError(error.MissingStorage, ctx.reserveScratch(1));
    try t.expectError(error.MissingStorage, ctx.reserveScratchAligned(1, 8));
    try t.expectError(error.MissingStorage, ctx.reserveRender(1));
    try t.expectError(error.MissingStorage, ctx.reserveRenderAligned(1, 8));
    try t.expectError(error.MissingStorage, ctx.reservePersistent(1));
    try t.expectError(error.MissingStorage, ctx.reservePersistentAligned(1, 8));
    try ctx.endFrame();
    try ctx.releaseFrame();

    // Configured-but-full keeps reporting OutOfCapacity from the arena/table.
    var scratch: [4]u8 = undefined;
    var render: [4]u8 = undefined;
    var persistent: [4]u8 = undefined;
    var entries: [1]widget_state.Entry = undefined;
    try ctx.setBuffers(&scratch, &render);
    try ctx.setPersistentBuffer(&persistent);
    try ctx.setStateStorage(&entries);
    try ctx.beginFrame(frame);
    _ = try ctx.reserveScratch(4);
    try t.expectError(error.OutOfCapacity, ctx.reserveScratch(1));
    _ = try ctx.reserveRender(4);
    try t.expectError(error.OutOfCapacity, ctx.reserveRender(1));
    _ = try ctx.reservePersistent(4);
    try t.expectError(error.OutOfCapacity, ctx.reservePersistent(1));
    _ = try ctx.widgetState(1);
    try t.expectError(error.OutOfCapacity, ctx.widgetState(2));
    try ctx.endFrame();
    try ctx.releaseFrame();
}
