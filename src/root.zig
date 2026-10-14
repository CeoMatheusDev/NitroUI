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
pub const font = @import("font.zig");
pub const text = @import("text.zig");
pub const text_edit = @import("text_edit.zig");
pub const text_input = @import("text_input.zig");

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

    /// Emit one line of UTF-8 text from a baseline origin using engine-owned font data.
    pub fn drawTextBaseline(self: *Context, font_data: font.Font, utf8: []const u8, baseline: [2]f32, scale: f32, color: u32, clip_rect: draw.ClipRect) (Error || text.Error || font.Error || draw.Error)!text.Metrics {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.geometry) |*buffer| return text.emitBaseline(buffer, font_data, utf8, baseline, scale, color, clip_rect);
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

    /// Begin a horizontal layout region; child items require explicit widths.
    pub fn pushHorizontalLayout(self: *Context, bounds: layout.Rect, spacing: layout.Spacing) (Error || layout.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        try self.layout_stack.pushHorizontal(bounds, spacing);
    }

    pub fn nextLayoutRect(self: *Context, width: ?f32, height: f32) (Error || layout.Error)!layout.Rect {
        if (self.state != .building) return error.InvalidFrameState;
        return self.layout_stack.next(width, height);
    }

    /// Reserve a rectangle with cross-axis alignment in the active region.
    pub fn nextAlignedLayoutRect(self: *Context, width: ?f32, height: f32, alignment: layout.Alignment) (Error || layout.Error)!layout.Rect {
        if (self.state != .building) return error.InvalidFrameState;
        return self.layout_stack.nextAligned(width, height, alignment);
    }

    /// Fill the remaining main-axis space of the current layout region.
    /// Cross-axis extent is explicit; no implicit resizing of prior items.
    pub fn nextFillRemainingLayoutRect(self: *Context, cross_size: f32) (Error || layout.Error)!layout.Rect {
        if (self.state != .building) return error.InvalidFrameState;
        return self.layout_stack.nextFillRemaining(cross_size);
    }

    /// Reserve a proportional share of remaining space without sibling reflow.
    /// `future_items` reserves spacing for every subsequent sibling.
    pub fn nextWeightedLayoutRect(self: *Context, weight: f32, remaining_weight: f32, future_items: usize, cross_size: f32) (Error || layout.Error)!layout.Rect {
        if (self.state != .building) return error.InvalidFrameState;
        return self.layout_stack.nextWeighted(weight, remaining_weight, future_items, cross_size);
    }

    /// Reserve one line using font metrics; no geometry is emitted.
    /// Baseline for drawTextBaseline: .{ rect.x, rect.y + font_data.ascent * scale }.
    pub fn nextTextLayoutRect(self: *Context, font_data: font.Font, utf8: []const u8, scale: f32) (Error || layout.Error || text.Error || font.Error)!layout.Rect {
        if (self.state != .building) return error.InvalidFrameState;
        return self.layout_stack.nextText(font_data, utf8, scale);
    }

    /// Place and render a single-line, non-interactive label in the current layout.
    /// The engine owns the font glyphs and atlas texture. No ID or widget state is used.
    /// On error both layout advancement and visible draw counts are preserved.
    pub fn label(self: *Context, font_data: font.Font, utf8: []const u8, scale: f32, color: u32, clip_rect: draw.ClipRect) (Error || layout.Error || text.Error || font.Error || draw.Error)!layout.Rect {
        if (self.state != .building) return error.InvalidFrameState;
        if (self.geometry == null) return error.MissingGeometry;
        const previous_layout = self.layout_stack;
        errdefer self.layout_stack = previous_layout;
        const rect = try self.layout_stack.nextText(font_data, utf8, scale);
        const baseline_y = rect.y + font_data.ascent * scale;
        if (!std.math.isFinite(baseline_y)) return error.CoordinateOverflow;
        _ = try self.drawTextBaseline(font_data, utf8, .{ rect.x, baseline_y }, scale, color, clip_rect);
        return rect;
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
    pub fn widgetId(self: *const Context, widget_label: []const u8) (Error)!ids.Id {
        if (self.state != .building) return error.InvalidFrameState;
        return self.id_stack.idString(widget_label);
    }

    pub fn pushId(self: *Context, widget_label: []const u8) (Error || ids.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        try self.id_stack.pushString(widget_label);
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

    /// Submit a widget with explicit keyboard/pointer eligibility.
    /// Disabled items are excluded from navigation but remain ID-trackable.
    pub fn interactEnabled(self: *Context, id: ids.Id, rect: layout.Rect, enabled: bool) (Error || interaction.Error)!interaction.Result {
        if (self.state != .building) return error.InvalidFrameState;
        return self.interaction_state.itemEnabled(id, rect, self.input_processor.snapshot, enabled);
    }

    /// Request keyboard focus for an item that will be submitted in this frame.
    /// Focus is discarded at endFrame if that item was not submitted.
    pub fn requestFocus(self: *Context, id: ids.Id) (Error || interaction.Error)!void {
        if (self.state != .building) return error.InvalidFrameState;
        try self.interaction_state.requestFocus(id);
    }

    /// Query the current keyboard focus without modifying state.
    pub fn focusedId(self: *const Context) ?ids.Id {
        return self.interaction_state.focused_id;
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

    /// Configure caller-owned navigation history and current-frame order.
    /// Both buffers must be disjoint from one another and all attached storage.
    pub fn setNavigationStorage(self: *Context, previous: ?[]ids.Id, current: ?[]ids.Id) (Error || interaction.Error)!void {
        if (self.state != .idle) return error.InvalidFrameState;
        if ((previous == null) != (current == null)) return error.NavigationCapacity;
        if (previous) |p| {
            const a = std.mem.sliceAsBytes(p);
            const b = std.mem.sliceAsBytes(current.?);
            if (p.len == 0 or current.?.len == 0) return error.NavigationCapacity;
            try ensureDisjoint(a, b);
            for ([_][]const u8{ a, b }) |bytes| {
                if (self.scratch) |arena| try ensureDisjoint(bytes, arena.storage);
                if (self.render) |arena| try ensureDisjoint(bytes, arena.storage);
                if (self.persistent) |arena| try ensureDisjoint(bytes, arena.storage);
                if (self.states) |table| {
                    const state_bytes = @as([*]const u8, @ptrCast(table.entries.ptr))[0 .. table.entries.len * @sizeOf(widget_state.Entry)];
                    try ensureDisjoint(bytes, state_bytes);
                }
                if (self.geometry) |g| try ensureGeometryDisjoint(bytes, g);
                if (self.interaction_state.visited_ids) |tracked| try ensureDisjoint(bytes, std.mem.sliceAsBytes(tracked));
            }
        }
        try self.interaction_state.setNavigationStorage(previous, current);
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

    fn checkpointWidget(self: *Context) (Error || draw.Error)!WidgetCheckpoint {
        if (self.state != .building) return error.InvalidFrameState;
        const buffer = self.geometry orelse return error.MissingGeometry;
        // Context exposes geometry publicly. Reject invalid logical prefixes
        // before a widget can read the previous draw command or emit data.
        if (buffer.vertex_count > buffer.vertices.len or
            buffer.index_count > buffer.indices.len or
            buffer.command_count > buffer.commands.len)
            return error.OutOfCapacity;
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
        const keyboard_clicked = try self.interaction_state.keyboardActivate(id, self.input_processor.snapshot);
        return result.clicked or keyboard_clicked;
    }

    /// Button with centered single-line UTF-8 caption. The caller owns the font,
    /// atlas, ID and bounds. Uses the same interaction path as button().
    /// On error restores pointer capture and logical geometry counts.
    pub fn buttonText(self: *Context, id: ids.Id, rect: layout.Rect, caption: []const u8, font_data: font.Font, scale: f32, text_color: u32, clip_rect: draw.ClipRect) (Error || interaction.Error || draw.Error || text.Error || font.Error)!bool {
        const checkpoint = try self.checkpointWidget();
        errdefer self.rollbackWidget(checkpoint);

        // Reject malformed text before claiming the widget ID or pointer capture.
        const metrics = try text.measure(font_data, caption, scale);
        const line_height = (font_data.ascent - font_data.descent + font_data.line_gap) * scale;
        if (!std.math.isFinite(line_height) or line_height <= 0) return error.InvalidScale;
        const baseline_x = rect.x + (rect.width - metrics.advance_x) * 0.5;
        const baseline_y = rect.y + (rect.height - line_height) * 0.5 + font_data.ascent * scale;
        if (!std.math.isFinite(baseline_x) or !std.math.isFinite(baseline_y)) return error.InvalidPosition;

        const result = try self.interact(id, rect);
        const color: u32 = if (result.held) self.visual_style.colors.button_active else if (result.hovered) self.visual_style.colors.button_hovered else self.visual_style.colors.button;
        try self.drawRect(rect.x, rect.y, rect.x + rect.width, rect.y + rect.height, color, 0, clip_rect);
        _ = try self.drawTextBaseline(font_data, caption, .{ baseline_x, baseline_y }, scale, text_color, clip_rect);
        const keyboard_clicked = try self.interaction_state.keyboardActivate(id, self.input_processor.snapshot);
        return result.clicked or keyboard_clicked;
    }

    /// Clip a single-line field to its content area, preserving the caller clip.
    /// An empty intersection is represented by a zero-area clip rectangle.
    fn inputTextContentClip(rect: layout.Rect, padding_x: f32, outer: draw.ClipRect) draw.Error!draw.ClipRect {
        if (!std.math.isFinite(outer.min_x) or !std.math.isFinite(outer.min_y) or
            !std.math.isFinite(outer.max_x) or !std.math.isFinite(outer.max_y) or
            outer.max_x < outer.min_x or outer.max_y < outer.min_y) return error.InvalidClip;
        if (!std.math.isFinite(rect.x) or !std.math.isFinite(rect.y) or
            !std.math.isFinite(rect.width) or !std.math.isFinite(rect.height) or
            !std.math.isFinite(padding_x) or padding_x < 0 or
            rect.width < 0 or rect.height < 0) return error.InvalidGeometry;
        const left = rect.x + padding_x;
        const right = rect.x + rect.width - padding_x;
        const bottom = rect.y + rect.height;
        if (!std.math.isFinite(left) or !std.math.isFinite(right) or !std.math.isFinite(bottom)) return error.InvalidGeometry;
        const min_x = @max(outer.min_x, left);
        const min_y = @max(outer.min_y, rect.y);
        const max_x = @max(min_x, @min(outer.max_x, right));
        const max_y = @max(min_y, @min(outer.max_y, bottom));
        return .{ .min_x = min_x, .min_y = min_y, .max_x = max_x, .max_y = max_y };
    }

    /// Horizontal offset in text pixels. The caller persists the value across frames.
    /// The caret is kept inside the content viewport; the offset is never negative.
    fn inputTextScrollOffset(previous: f32, caret_advance: f32, content_width: f32) text.Error!f32 {
        if (!std.math.isFinite(previous) or previous < 0 or
            !std.math.isFinite(caret_advance) or caret_advance < 0 or
            !std.math.isFinite(content_width) or content_width < 0) return error.InvalidPosition;
        if (content_width == 0) return caret_advance;
        const right = previous + content_width;
        if (!std.math.isFinite(right)) return error.InvalidPosition;
        if (caret_advance < previous) return caret_advance;
        if (caret_advance > right) return caret_advance - content_width;
        return previous;
    }

    /// Advances horizontal scroll while a captured pointer is outside the
    /// content viewport. Caller supplies the engine delta time; the rate is
    /// bounded and independent of frame frequency. No allocations.
    fn inputTextDragAutoScroll(previous: f32, pointer_x: f32, left: f32, right: f32, delta_seconds: f32) text.Error!f32 {
        if (!std.math.isFinite(previous) or previous < 0 or
            !std.math.isFinite(pointer_x) or !std.math.isFinite(left) or
            !std.math.isFinite(right) or right < left or
            !std.math.isFinite(delta_seconds) or delta_seconds < 0)
            return error.InvalidPosition;
        if (delta_seconds == 0 or left == right) return previous;
        const overflow: f32 = if (pointer_x < left) pointer_x - left else if (pointer_x > right) pointer_x - right else 0;
        if (overflow == 0) return previous;
        // Cap velocity and elapsed time to avoid jumps after long pauses.
        const speed = @min(@abs(overflow) * 8.0 + 80.0, 1200.0);
        const step = speed * @min(delta_seconds, 0.1);
        const result = if (overflow < 0) @max(0.0, previous - step) else previous + step;
        if (!std.math.isFinite(result)) return error.InvalidPosition;
        return result;
    }

    /// Failure policy for editable widgets: successful edits to caller-owned
    /// text are retained if later geometry emission fails. Only NitroUI-owned
    /// geometry/interaction checkpoints are rolled back. The engine MUST NOT
    /// replay already-applied input events after a rendering error. Use
    /// inputTextDraggedTracked to observe the consumed prefix even when the
    /// visual widget returns an error; the untracked variants do not expose it.
    /// This policy avoids copying the entire caller-owned text buffer per frame.
    pub const TextRenderFailurePolicy = enum { retain_edits };
    pub const text_render_failure_policy: TextRenderFailurePolicy = .retain_edits;

    /// Initial single-line UTF-8 field. Events must be supplied in order by the
    /// engine, not reconstructed from the last Processor batch. The caller owns
    /// editor storage and keeps it alive across frames. This first visual pass
    /// uses temporary horizontal scrolling; use inputTextScrolled to persist it.
    /// Text edits can persist if a subsequent geometry emission fails.
    pub fn inputText(self: *Context, id: ids.Id, rect: layout.Rect, editor: *text_edit.Buffer, events: []const input_events.Event, initial_shift: bool, font_data: font.Font, scale: f32, text_color: u32, clip_rect: draw.ClipRect) (Error || interaction.Error || draw.Error || text.Error || font.Error || text_edit.Error)!usize {
        var temporary_scroll: f32 = 0;
        return self.inputTextScrolled(id, rect, editor, events, initial_shift, font_data, scale, text_color, clip_rect, &temporary_scroll);
    }

    /// Scrolling variant of inputText. `horizontal_scroll` is caller-owned,
    /// persistent between frames, and committed only after geometry succeeds.
    /// The scroll offset is expressed in the same pixels as text metrics.
    pub fn inputTextScrolled(self: *Context, id: ids.Id, rect: layout.Rect, editor: *text_edit.Buffer, events: []const input_events.Event, initial_shift: bool, font_data: font.Font, scale: f32, text_color: u32, clip_rect: draw.ClipRect, horizontal_scroll: *f32) (Error || interaction.Error || draw.Error || text.Error || font.Error || text_edit.Error)!usize {
        return self.inputTextDraggedInternal(id, rect, editor, events, initial_shift, font_data, scale, text_color, clip_rect, horizontal_scroll, null);
    }

    /// Drag-selection variant. `drag_anchor` is caller-owned persistent state;
    /// keep it between frames and initialize it to null. Only the primary
    /// pointer capture belonging to this widget updates the selection.
    pub fn inputTextDragged(self: *Context, id: ids.Id, rect: layout.Rect, editor: *text_edit.Buffer, events: []const input_events.Event, initial_shift: bool, font_data: font.Font, scale: f32, text_color: u32, clip_rect: draw.ClipRect, horizontal_scroll: *f32, drag_anchor: *?usize) (Error || interaction.Error || draw.Error || text.Error || font.Error || text_edit.Error)!usize {
        return self.inputTextDraggedInternal(id, rect, editor, events, initial_shift, font_data, scale, text_color, clip_rect, horizontal_scroll, drag_anchor);
    }

    /// Tracked variant for applications that must recover from partial event
    /// processing or a subsequent rendering failure. `progress` is reset at
    /// entry. It counts only events applied by the text-input bridge, not
    /// pointer interactions. On draw failure, already-consumed events remain
    /// applied and MUST NOT be replayed. No allocations or text copies.
    pub fn inputTextDraggedTracked(self: *Context, id: ids.Id, rect: layout.Rect, editor: *text_edit.Buffer, events: []const input_events.Event, initial_shift: bool, font_data: font.Font, scale: f32, text_color: u32, clip_rect: draw.ClipRect, horizontal_scroll: *f32, drag_anchor: *?usize, progress: *text_input.Progress) (Error || interaction.Error || draw.Error || text.Error || font.Error || text_edit.Error)!usize {
        progress.* = .{ .shift = initial_shift, .focused = false };
        return self.inputTextDraggedInternalTracked(id, rect, editor, events, initial_shift, font_data, scale, text_color, clip_rect, horizontal_scroll, drag_anchor, progress);
    }

    fn inputTextDraggedInternal(self: *Context, id: ids.Id, rect: layout.Rect, editor: *text_edit.Buffer, events: []const input_events.Event, initial_shift: bool, font_data: font.Font, scale: f32, text_color: u32, clip_rect: draw.ClipRect, horizontal_scroll: *f32, drag_anchor: ?*?usize) (Error || interaction.Error || draw.Error || text.Error || font.Error || text_edit.Error)!usize {
        var progress: text_input.Progress = .{};
        return self.inputTextDraggedInternalTracked(id, rect, editor, events, initial_shift, font_data, scale, text_color, clip_rect, horizontal_scroll, drag_anchor, &progress);
    }

    fn inputTextDraggedInternalTracked(self: *Context, id: ids.Id, rect: layout.Rect, editor: *text_edit.Buffer, events: []const input_events.Event, initial_shift: bool, font_data: font.Font, scale: f32, text_color: u32, clip_rect: draw.ClipRect, horizontal_scroll: *f32, drag_anchor: ?*?usize, progress: *text_input.Progress) (Error || interaction.Error || draw.Error || text.Error || font.Error || text_edit.Error)!usize {
        progress.* = .{ .shift = initial_shift, .focused = false };
        const checkpoint = try self.checkpointWidget();
        errdefer self.rollbackWidget(checkpoint);

        // Reject externally invalidated cursor/selection and scroll before
        // claiming interaction or changing caller-owned edit state.
        try editor.validateState();
        if (!std.math.isFinite(horizontal_scroll.*) or horizontal_scroll.* < 0) return error.InvalidPosition;
        // Validate the existing text and geometry before claiming interaction.
        _ = try text.measure(font_data, editor.view(), scale);
        const line_height = (font_data.ascent - font_data.descent + font_data.line_gap) * scale;
        if (!std.math.isFinite(line_height) or line_height <= 0) return error.InvalidScale;
        if (!std.math.isFinite(rect.x) or !std.math.isFinite(rect.y) or !std.math.isFinite(rect.width) or !std.math.isFinite(rect.height)) return error.InvalidPosition;
        const baseline_x = rect.x + self.visual_style.frame_padding_x;
        const baseline_y = rect.y + (rect.height - line_height) * 0.5 + font_data.ascent * scale;
        if (!std.math.isFinite(baseline_x) or !std.math.isFinite(baseline_y)) return error.InvalidPosition;

        const content_clip = try inputTextContentClip(rect, self.visual_style.frame_padding_x, clip_rect);
        const result = try self.interact(id, rect);
        // A failed widget rolls back its interaction checkpoint. Invalidate the
        // caller-owned drag anchor as well: the restored capture state cannot
        // safely justify continuing an in-progress drag on the next frame.
        // Preflight failures above deliberately leave the anchor untouched.
        errdefer {
            if (drag_anchor) |anchor| anchor.* = null;
        }
        // Pointer-down places the caret at the nearest UTF-8 scalar boundary.
        // The hit test uses the previous scroll offset, before keyboard edits
        // and before the next scroll position is calculated.
        // A drag is valid only while this widget owns primary capture and the
        // window remains focused. Clear stale anchors before hit testing, so a
        // release outside the widget or a focus loss cannot resume an old drag.
        if (drag_anchor) |anchor| {
            if (!dragCaptureValid(self.interaction_state.active_id, id, self.input_processor.snapshot, result)) {
                anchor.* = null;
            }
        }
        var drag_scroll = horizontal_scroll.*;
        const dragging = drag_anchor != null and result.held and drag_anchor.?.* != null and !result.pressed;
        if (dragging) {
            const dt: f32 = if (self.input) |frame| frame.delta_seconds else 0;
            drag_scroll = try inputTextDragAutoScroll(
                horizontal_scroll.*,
                self.input_processor.snapshot.pointer_x,
                content_clip.min_x,
                content_clip.max_x,
                dt,
            );
        }
        if (result.pressed or dragging) {
            const local_x = self.input_processor.snapshot.pointer_x - baseline_x + drag_scroll;
            const offset = try text.caretOffsetAtX(font_data, editor.view(), scale, local_x);
            if (result.pressed) {
                try editor.setCursor(offset);
                if (drag_anchor) |anchor| anchor.* = offset;
            } else if (drag_anchor) |anchor| {
                try editor.select(anchor.*.?, offset);
            }
        }
        const focused = self.focusedId() != null and self.focusedId().? == id and self.input_processor.snapshot.focused;
        try text_input.applyTracked(editor, events, initial_shift, focused, progress);
        const changes = progress.changes;
        const content = editor.view();
        const metrics = try text.measure(font_data, content, scale);
        const caret_metrics = try text.measure(font_data, content[0..editor.cursor], scale);
        const viewport_width = content_clip.max_x - content_clip.min_x;
        const next_scroll = try inputTextScrollOffset(drag_scroll, caret_metrics.advance_x, viewport_width);
        const text_x = baseline_x - next_scroll;
        if (!std.math.isFinite(text_x)) return error.InvalidPosition;
        const color: u32 = if (focused) self.visual_style.colors.button_active else if (result.hovered) self.visual_style.colors.button_hovered else self.visual_style.colors.button;
        try self.drawRect(rect.x, rect.y, rect.x + rect.width, rect.y + rect.height, color, 0, clip_rect);

        if (focused) {
            if (editor.selection()) |range| {
                const before = try text.measure(font_data, content[0..range.start], scale);
                const selected = try text.measure(font_data, content[0..range.end], scale);
                try self.drawRect(text_x + before.advance_x, baseline_y - font_data.ascent * scale, text_x + selected.advance_x, baseline_y - font_data.descent * scale, 0xff986f42, 0, content_clip);
            }
        }
        _ = metrics;
        _ = try self.drawTextBaseline(font_data, content, .{ text_x, baseline_y }, scale, text_color, content_clip);
        if (focused) {
            const caret_x = text_x + caret_metrics.advance_x;
            try self.drawRect(caret_x, baseline_y - font_data.ascent * scale, caret_x + 1, baseline_y - font_data.descent * scale, text_color, 0, content_clip);
        }
        horizontal_scroll.* = next_scroll;
        return changes;
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

    /// Checkbox with a single-line UTF-8 caption. The full row is interactive;
    /// the square indicator is placed on the left and vertically centered.
    /// `value` is committed only after all geometry has been emitted successfully.
    /// Caller owns the font, atlas, ID, bounds, and boolean storage.
    pub fn checkboxText(self: *Context, id: ids.Id, rect: layout.Rect, value: *bool, caption: []const u8, font_data: font.Font, scale: f32, text_color: u32, clip_rect: draw.ClipRect) (Error || interaction.Error || draw.Error || text.Error || font.Error)!bool {
        const checkpoint = try self.checkpointWidget();
        errdefer self.rollbackWidget(checkpoint);

        const metrics = try text.measure(font_data, caption, scale);
        const line_height = (font_data.ascent - font_data.descent + font_data.line_gap) * scale;
        if (!std.math.isFinite(line_height) or line_height <= 0) return error.InvalidScale;
        if (!std.math.isFinite(rect.x) or !std.math.isFinite(rect.y) or
            !std.math.isFinite(rect.width) or !std.math.isFinite(rect.height) or
            rect.width <= 0 or rect.height <= 0) return error.InvalidGeometry;

        const box_size = @min(rect.height, line_height);
        const gap = box_size * 0.25;
        const box_x = rect.x;
        const box_y = rect.y + (rect.height - box_size) * 0.5;
        const text_x = rect.x + box_size + gap;
        const baseline_y = rect.y + (rect.height - line_height) * 0.5 + font_data.ascent * scale;
        if (!std.math.isFinite(box_y) or !std.math.isFinite(text_x) or
            !std.math.isFinite(baseline_y) or
            !std.math.isFinite(text_x + metrics.advance_x) or
            !std.math.isFinite(box_x + box_size) or !std.math.isFinite(box_y + box_size)) return error.InvalidPosition;

        const result = try self.interact(id, rect);
        const color: u32 = if (result.hovered) self.visual_style.colors.checkbox_hovered else self.visual_style.colors.checkbox;
        try self.drawRect(box_x, box_y, box_x + box_size, box_y + box_size, color, 0, clip_rect);
        // Render the state that will be committed on success, without modifying
        // caller-owned data before all fallible draw operations complete.
        const next_value = if (result.clicked) !value.* else value.*;
        if (next_value) {
            const inset = box_size * 0.25;
            try self.drawRect(box_x + inset, box_y + inset, box_x + box_size - inset, box_y + box_size - inset, self.visual_style.colors.checkmark, 0, clip_rect);
        }
        _ = try self.drawTextBaseline(font_data, caption, .{ text_x, baseline_y }, scale, text_color, clip_rect);
        value.* = next_value;
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

    /// Slider with a UTF-8 caption and a fixed two-decimal value readout.
    /// The upper portion contains text; the lower portion is the interactive track.
    /// Caller-owned scalar is committed only after all rendering succeeds.
    /// Formatting uses a fixed stack buffer and performs no heap allocation.
    pub fn sliderFloatText(self: *Context, id: ids.Id, rect: layout.Rect, value: *f32, min: f32, max: f32, caption: []const u8, font_data: font.Font, scale: f32, text_color: u32, clip_rect: draw.ClipRect) (Error || interaction.Error || draw.Error || text.Error || font.Error)!bool {
        const checkpoint = try self.checkpointWidget();
        errdefer self.rollbackWidget(checkpoint);

        // Perform all text and geometry validation before interaction changes.
        const caption_metrics = try text.measure(font_data, caption, scale);
        const line_height = (font_data.ascent - font_data.descent + font_data.line_gap) * scale;
        if (!std.math.isFinite(line_height) or line_height <= 0) return error.InvalidScale;
        if (!std.math.isFinite(rect.x) or !std.math.isFinite(rect.y) or
            !std.math.isFinite(rect.width) or !std.math.isFinite(rect.height) or
            rect.width <= 0 or rect.height <= line_height or
            !std.math.isFinite(rect.y + rect.height) or
            !std.math.isFinite(rect.x + rect.width)) return error.InvalidGeometry;
        if (!std.math.isFinite(min) or !std.math.isFinite(max) or !(max > min) or
            !std.math.isFinite(max - min) or !std.math.isFinite(value.*)) return error.InvalidGeometry;

        const track_y = rect.y + line_height;
        const track_height = rect.height - line_height;
        if (!std.math.isFinite(track_y) or !std.math.isFinite(track_height) or track_height <= 0) return error.InvalidGeometry;
        const track: layout.Rect = .{ .x = rect.x, .y = track_y, .width = rect.width, .height = track_height };
        const previous = value.*;
        errdefer value.* = previous;
        const changed = try self.sliderFloat(id, track, value, min, max, clip_rect);

        var value_buffer: [64]u8 = undefined;
        const value_text = std.fmt.bufPrint(&value_buffer, "{d:.2}", .{value.*}) catch return error.InvalidGeometry;
        const value_metrics = try text.measure(font_data, value_text, scale);
        const caption_x = rect.x;
        const value_x = rect.x + rect.width - value_metrics.advance_x;
        const baseline_y = rect.y + font_data.ascent * scale;
        if (!std.math.isFinite(caption_x + caption_metrics.advance_x) or
            !std.math.isFinite(value_x) or !std.math.isFinite(baseline_y)) return error.InvalidPosition;
        _ = try self.drawTextBaseline(font_data, caption, .{ caption_x, baseline_y }, scale, text_color, clip_rect);
        _ = try self.drawTextBaseline(font_data, value_text, .{ value_x, baseline_y }, scale, text_color, clip_rect);
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

/// Drag selection is only live while the primary button remains down and
/// interaction capture belongs to this exact widget. A release (including
/// outside the widget) or window focus loss invalidates caller-owned anchor.
fn dragCaptureValid(active_id: ?ids.Id, id: ids.Id, snapshot: input_events.Snapshot, result: interaction.Result) bool {
    return snapshot.focused and (snapshot.buttons_down & 1) != 0 and
        !snapshot.primary_released and active_id != null and active_id.? == id and
        (result.held or result.pressed);
}

test "drag capture persists outside bounds and ends on release" {
    const testing = std.testing;
    const id: ids.Id = 41;
    const held: interaction.Result = .{ .held = true };
    try testing.expect(dragCaptureValid(id, id, .{ .buttons_down = 1, .pointer_x = -50 }, held));
    try testing.expect(!dragCaptureValid(id, id, .{ .buttons_down = 0, .primary_released = true }, .{}));
    try testing.expect(!dragCaptureValid(id, id, .{ .buttons_down = 1, .focused = false }, held));
}

test "drag capture rejects another widget and stale primary button" {
    const testing = std.testing;
    const id: ids.Id = 41;
    const held: interaction.Result = .{ .held = true };
    try testing.expect(!dragCaptureValid(@as(ids.Id, 42), id, .{ .buttons_down = 1 }, held));
    try testing.expect(!dragCaptureValid(null, id, .{ .buttons_down = 1 }, held));
    try testing.expect(!dragCaptureValid(id, id, .{ .buttons_down = 0 }, held));
    try testing.expect(!dragCaptureValid(id, id, .{ .buttons_down = 1, .primary_released = true }, held));
}

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

// Include text/font contract tests in the root test suite.
test {
    _ = @import("font.zig");
    _ = @import("text.zig");
    _ = @import("text_edit.zig");
}

test "stage25_5 label emits text and advances layout" {
    const t = std.testing;
    const glyphs = [_]font.Glyph{.{ .codepoint = 65, .advance_x = 7, .bearing_x = 0, .bearing_y = 8, .width = 6, .height = 9, .u0 = 0, .v0 = 0, .u1 = 1, .v1 = 1 }};
    const f: font.Font = .{ .glyphs = &glyphs, .texture = 12, .ascent = 9, .descent = -3, .line_gap = 2 };
    var vertices: [12]draw.Vertex = undefined;
    var indices: [18]u32 = undefined;
    var commands: [2]draw.Command = undefined;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    const clip_rect: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } });
    try ctx.pushLayout(.{ .x = 10, .y = 20, .width = 80, .height = 70 }, .{ .y = 3 });
    const first = try ctx.label(f, "AA", 1, 0xffffffff, clip_rect);
    try t.expectEqual(@as(f32, 14), first.width);
    try t.expectEqual(@as(f32, 14), first.height);
    try t.expectEqual(@as(f32, 20), first.y);
    const second = try ctx.label(f, "A", 1, 0xffffffff, clip_rect);
    try t.expectEqual(@as(f32, 37), second.y);
    try t.expectEqual(@as(usize, 12), ctx.geometry.?.vertex_count);
    try t.expectEqual(@as(usize, 18), ctx.geometry.?.index_count);
    try t.expectEqual(@as(usize, 1), ctx.geometry.?.command_count);
    try ctx.popLayout();
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "stage25_5 label failure rolls back layout and geometry" {
    const t = std.testing;
    const glyphs = [_]font.Glyph{.{ .codepoint = 65, .advance_x = 7, .bearing_x = 0, .bearing_y = 8, .width = 6, .height = 9, .u0 = 0, .v0 = 0, .u1 = 1, .v1 = 1 }};
    const f: font.Font = .{ .glyphs = &glyphs, .texture = 12, .ascent = 9, .descent = -3, .line_gap = 2 };
    var vertices: [4]draw.Vertex = undefined;
    var indices: [6]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    const clip_rect: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try t.expectError(error.InvalidFrameState, ctx.label(f, "A", 1, 0xffffffff, clip_rect));
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } });
    try ctx.pushLayout(.{ .x = 0, .y = 0, .width = 100, .height = 100 }, .{ .y = 2 });
    try t.expectError(error.InvalidUtf8, ctx.label(f, &.{0xff}, 1, 0xffffffff, clip_rect));
    try t.expectError(error.OutOfCapacity, ctx.label(f, "AA", 1, 0xffffffff, clip_rect));
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.vertex_count);
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.command_count);
    const rect = try ctx.label(f, "A", 1, 0xffffffff, clip_rect);
    try t.expectEqual(@as(f32, 0), rect.y);
    try t.expectEqual(@as(usize, 4), ctx.geometry.?.vertex_count);
    try ctx.popLayout();
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "horizontal layout context requires building frame" {
    const t = std.testing;
    var ctx: Context = .{};
    const bounds: layout.Rect = .{ .x = 10, .y = 20, .width = 100, .height = 30 };
    try t.expectError(error.InvalidFrameState, ctx.pushHorizontalLayout(bounds, .{}));
}

test "aligned layout context requires building frame" {
    const t = std.testing;
    var ctx: Context = .{};
    try t.expectError(error.InvalidFrameState, ctx.nextAlignedLayoutRect(10, 5, .center));
}

test "fill remaining context operation requires building frame" {
    const t = std.testing;
    var ctx: Context = .{};
    try t.expectError(error.InvalidFrameState, ctx.nextFillRemainingLayoutRect(5));
}

test "weighted layout context requires building frame" {
    const t = std.testing;
    var ctx: Context = .{};
    try t.expectError(error.InvalidFrameState, ctx.nextWeightedLayoutRect(1, 2, 1, 10));
}

test "stage27_0 buttonText emits background and centered caption" {
    const t = std.testing;
    const glyphs = [_]font.Glyph{.{ .codepoint = 65, .advance_x = 8, .bearing_x = 0, .bearing_y = 8, .width = 6, .height = 9, .u0 = 0, .v0 = 0, .u1 = 1, .v1 = 1 }};
    const f: font.Font = .{ .glyphs = &glyphs, .texture = 42, .ascent = 9, .descent = -3, .line_gap = 2 };
    var vertices: [12]draw.Vertex = undefined;
    var indices: [18]u32 = undefined;
    var commands: [3]draw.Command = undefined;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    const clip_rect: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try t.expectError(error.InvalidFrameState, ctx.buttonText(1, .{ .x = 0, .y = 0, .width = 40, .height = 20 }, "A", f, 1, 0xffffffff, clip_rect));
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } });
    try t.expect(!(try ctx.buttonText(1, .{ .x = 10, .y = 10, .width = 40, .height = 20 }, "A", f, 1, 0xffffffff, clip_rect)));
    try t.expectEqual(@as(usize, 8), ctx.geometry.?.vertex_count);
    try t.expectEqual(@as(usize, 12), ctx.geometry.?.index_count);
    try t.expectEqual(@as(usize, 2), ctx.geometry.?.command_count);
    try t.expectEqual(@as(f32, 26), ctx.geometry.?.vertices[4].x);
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "stage27_0 buttonText restores geometry and ID tracking after text capacity failure" {
    const t = std.testing;
    const glyphs = [_]font.Glyph{.{ .codepoint = 65, .advance_x = 8, .bearing_x = 0, .bearing_y = 8, .width = 6, .height = 9, .u0 = 0, .v0 = 0, .u1 = 1, .v1 = 1 }};
    const f: font.Font = .{ .glyphs = &glyphs, .texture = 42, .ascent = 9, .descent = -3, .line_gap = 2 };
    var vertices: [4]draw.Vertex = undefined;
    var indices: [6]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    var tracked: [2]ids.Id = undefined;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    try ctx.setInteractionIdStorage(&tracked);
    const clip_rect: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    const rect: layout.Rect = .{ .x = 10, .y = 10, .width = 40, .height = 20 };
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } });
    try t.expectError(error.InvalidUtf8, ctx.buttonText(1, rect, &.{0xff}, f, 1, 0xffffffff, clip_rect));
    try t.expectError(error.OutOfCapacity, ctx.buttonText(1, rect, "A", f, 1, 0xffffffff, clip_rect));
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.vertex_count);
    try t.expectEqual(@as(usize, 0), ctx.interaction_state.visited_count);
    // The same ID remains usable after both failures.
    try t.expect(!(try ctx.button(1, rect, clip_rect)));
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "stage27_1 checkboxText emits box and caption without changing value" {
    const t = std.testing;
    const glyphs = [_]font.Glyph{.{ .codepoint = 65, .advance_x = 8, .bearing_x = 0, .bearing_y = 8, .width = 6, .height = 9, .u0 = 0, .v0 = 0, .u1 = 1, .v1 = 1 }};
    const f: font.Font = .{ .glyphs = &glyphs, .texture = 42, .ascent = 9, .descent = -3, .line_gap = 2 };
    var vertices: [12]draw.Vertex = undefined;
    var indices: [18]u32 = undefined;
    var commands: [3]draw.Command = undefined;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    const region: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    const rect: layout.Rect = .{ .x = 10, .y = 10, .width = 70, .height = 20 };
    var checked = true;
    try t.expectError(error.InvalidFrameState, ctx.checkboxText(1, rect, &checked, "A", f, 1, 0xffffffff, region));
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } });
    try t.expect(!(try ctx.checkboxText(1, rect, &checked, "A", f, 1, 0xffffffff, region)));
    try t.expect(checked);
    try t.expectEqual(@as(usize, 12), ctx.geometry.?.vertex_count);
    try t.expectEqual(@as(usize, 18), ctx.geometry.?.index_count);
    try t.expectEqual(@as(usize, 2), ctx.geometry.?.command_count);
    try t.expectEqual(@as(f32, 27.5), ctx.geometry.?.vertices[8].x);
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "stage27_1 checkboxText rollback preserves caller value and ID after capacity failure" {
    const t = std.testing;
    const glyphs = [_]font.Glyph{.{ .codepoint = 65, .advance_x = 8, .bearing_x = 0, .bearing_y = 8, .width = 6, .height = 9, .u0 = 0, .v0 = 0, .u1 = 1, .v1 = 1 }};
    const f: font.Font = .{ .glyphs = &glyphs, .texture = 42, .ascent = 9, .descent = -3, .line_gap = 2 };
    var vertices: [4]draw.Vertex = undefined;
    var indices: [6]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    var tracked: [2]ids.Id = undefined;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    try ctx.setInteractionIdStorage(&tracked);
    const region: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    const rect: layout.Rect = .{ .x = 10, .y = 10, .width = 70, .height = 20 };
    var checked = true;
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } });
    try t.expectError(error.InvalidUtf8, ctx.checkboxText(1, rect, &checked, &.{0xff}, f, 1, 0xffffffff, region));
    try t.expectError(error.OutOfCapacity, ctx.checkboxText(1, rect, &checked, "A", f, 1, 0xffffffff, region));
    try t.expect(checked);
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.vertex_count);
    try t.expectEqual(@as(usize, 0), ctx.interaction_state.visited_count);
    try t.expect(!(try ctx.button(1, rect, region)));
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "stage27_2 sliderFloatText renders caption and value with caller-owned buffers" {
    const t = std.testing;
    const glyphs = [_]font.Glyph{.{ .codepoint = 63, .advance_x = 8, .bearing_x = 0, .bearing_y = 8, .width = 6, .height = 9, .u0 = 0, .v0 = 0, .u1 = 1, .v1 = 1 }};
    const f: font.Font = .{ .glyphs = &glyphs, .texture = 42, .ascent = 9, .descent = -3, .line_gap = 2, .fallback = 63 };
    var vertices: [128]draw.Vertex = undefined;
    var indices: [192]u32 = undefined;
    var commands: [16]draw.Command = undefined;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    const region: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 200, .max_y = 100 };
    const rect: layout.Rect = .{ .x = 10, .y = 10, .width = 120, .height = 32 };
    var value: f32 = 0.5;
    try t.expectError(error.InvalidFrameState, ctx.sliderFloatText(1, rect, &value, 0, 1, "A", f, 1, 0xffffffff, region));
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 200, .y = 100 } });
    try t.expect(!(try ctx.sliderFloatText(1, rect, &value, 0, 1, "A", f, 1, 0xffffffff, region)));
    try t.expectEqual(@as(f32, 0.5), value);
    try t.expectEqual(@as(usize, 28), ctx.geometry.?.vertex_count);
    try t.expectEqual(@as(usize, 42), ctx.geometry.?.index_count);
    try t.expectEqual(@as(usize, 2), ctx.geometry.?.command_count);
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "stage27_2 sliderFloatText rolls back geometry, IDs and value on errors" {
    const t = std.testing;
    const glyphs = [_]font.Glyph{.{ .codepoint = 63, .advance_x = 8, .bearing_x = 0, .bearing_y = 8, .width = 6, .height = 9, .u0 = 0, .v0 = 0, .u1 = 1, .v1 = 1 }};
    const f: font.Font = .{ .glyphs = &glyphs, .texture = 42, .ascent = 9, .descent = -3, .line_gap = 2, .fallback = 63 };
    var vertices: [8]draw.Vertex = undefined;
    var indices: [12]u32 = undefined;
    var commands: [2]draw.Command = undefined;
    var tracked: [2]ids.Id = undefined;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    try ctx.setInteractionIdStorage(&tracked);
    const region: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 200, .max_y = 100 };
    const rect: layout.Rect = .{ .x = 10, .y = 10, .width = 120, .height = 32 };
    var value: f32 = 0.5;
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 200, .y = 100 } });
    try t.expectError(error.InvalidUtf8, ctx.sliderFloatText(1, rect, &value, 0, 1, &.{0xff}, f, 1, 0xffffffff, region));
    try t.expectError(error.OutOfCapacity, ctx.sliderFloatText(1, rect, &value, 0, 1, "A", f, 1, 0xffffffff, region));
    try t.expectEqual(@as(f32, 0.5), value);
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.vertex_count);
    try t.expectEqual(@as(usize, 0), ctx.interaction_state.visited_count);
    try t.expect(!(try ctx.button(1, rect, region)));
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "stage27_3 widget checkpoint rejects corrupted public geometry counts" {
    const t = std.testing;
    var vertices: [4]draw.Vertex = undefined;
    var indices: [6]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    const region: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    const rect: layout.Rect = .{ .x = 10, .y = 10, .width = 30, .height = 20 };
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 100, .y = 100 } });

    ctx.geometry.?.command_count = 2;
    try t.expectError(error.OutOfCapacity, ctx.button(1, rect, region));
    try t.expectEqual(@as(usize, 2), ctx.geometry.?.command_count);
    ctx.geometry.?.command_count = 0;

    ctx.geometry.?.vertex_count = 5;
    try t.expectError(error.OutOfCapacity, ctx.button(1, rect, region));
    try t.expectEqual(@as(usize, 5), ctx.geometry.?.vertex_count);
    ctx.geometry.?.vertex_count = 0;

    ctx.geometry.?.index_count = 7;
    try t.expectError(error.OutOfCapacity, ctx.button(1, rect, region));
    try t.expectEqual(@as(usize, 7), ctx.geometry.?.index_count);
    ctx.geometry.?.index_count = 0;

    try t.expectEqual(@as(usize, 0), ctx.interaction_state.visited_count);
    try t.expect(!(try ctx.button(1, rect, region)));
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "stage28_13 input text content clip intersects caller and field" {
    const rect: layout.Rect = .{ .x = 10, .y = 20, .width = 100, .height = 30 };
    const outer: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 90, .max_y = 100 };
    const clipped = try Context.inputTextContentClip(rect, 8, outer);
    try std.testing.expectEqual(@as(f32, 18), clipped.min_x);
    try std.testing.expectEqual(@as(f32, 20), clipped.min_y);
    try std.testing.expectEqual(@as(f32, 90), clipped.max_x);
    try std.testing.expectEqual(@as(f32, 50), clipped.max_y);
}

test "stage28_13 input text content clip handles disjoint and invalid clips" {
    const rect: layout.Rect = .{ .x = 10, .y = 20, .width = 100, .height = 30 };
    const outside: draw.ClipRect = .{ .min_x = 200, .min_y = 200, .max_x = 250, .max_y = 250 };
    const empty = try Context.inputTextContentClip(rect, 8, outside);
    try std.testing.expectEqual(empty.min_x, empty.max_x);
    try std.testing.expectEqual(empty.min_y, empty.max_y);
    try std.testing.expectError(error.InvalidClip, Context.inputTextContentClip(rect, 8, .{ .min_x = 2, .min_y = 0, .max_x = 1, .max_y = 10 }));
}

test "input text horizontal offset keeps caret visible" {
    try std.testing.expectEqual(@as(f32, 0), try Context.inputTextScrollOffset(0, 12, 20));
    try std.testing.expectEqual(@as(f32, 15), try Context.inputTextScrollOffset(0, 35, 20));
    try std.testing.expectEqual(@as(f32, 5), try Context.inputTextScrollOffset(15, 5, 20));
    try std.testing.expectEqual(@as(f32, 15), try Context.inputTextScrollOffset(15, 20, 20));
    try std.testing.expectEqual(@as(f32, 30), try Context.inputTextScrollOffset(15, 30, 0));
}

test "input text horizontal offset rejects invalid values" {
    try std.testing.expectError(error.InvalidPosition, Context.inputTextScrollOffset(-1, 0, 20));
    try std.testing.expectError(error.InvalidPosition, Context.inputTextScrollOffset(0, -1, 20));
    try std.testing.expectError(error.InvalidPosition, Context.inputTextScrollOffset(0, 0, -1));
    try std.testing.expectError(error.InvalidPosition, Context.inputTextScrollOffset(std.math.inf(f32), 0, 20));
}

test "drag auto-scroll advances in both directions and clamps at zero" {
    const t = std.testing;
    try t.expectEqual(@as(f32, 100), try Context.inputTextDragAutoScroll(100, 50, 0, 100, 0.016));
    try t.expect((try Context.inputTextDragAutoScroll(100, 130, 0, 100, 0.016)) > 100);
    try t.expect((try Context.inputTextDragAutoScroll(100, -30, 0, 100, 0.016)) < 100);
    try t.expectEqual(@as(f32, 0), try Context.inputTextDragAutoScroll(0, -100, 0, 100, 0.1));
    try t.expectEqual(@as(f32, 100), try Context.inputTextDragAutoScroll(100, 130, 0, 100, 0));
}

test "drag auto-scroll rejects invalid geometry and time" {
    const t = std.testing;
    try t.expectError(error.InvalidPosition, Context.inputTextDragAutoScroll(0, 10, 100, 0, 0.016));
    try t.expectError(error.InvalidPosition, Context.inputTextDragAutoScroll(0, 10, 0, 100, -1));
    try t.expectError(error.InvalidPosition, Context.inputTextDragAutoScroll(-1, 10, 0, 100, 0.016));
    try t.expectError(error.InvalidPosition, Context.inputTextDragAutoScroll(0, std.math.inf(f32), 0, 100, 0.016));
}

// A rendering failure does not roll back already committed caller-owned edits.
// The widget checkpoint still rolls back geometry and ID bookkeeping.
test "stage28_22 text render capacity failure retains edit and rolls back widget" {
    const t = std.testing;
    const glyphs = [_]font.Glyph{.{ .codepoint = 63, .advance_x = 8, .bearing_x = 0, .bearing_y = 8, .width = 6, .height = 9, .u0 = 0, .v0 = 0, .u1 = 1, .v1 = 1 }};
    const f: font.Font = .{ .glyphs = &glyphs, .texture = 42, .ascent = 9, .descent = -3, .line_gap = 2, .fallback = 63 };
    var vertices: [0]draw.Vertex = .{};
    var indices: [0]u32 = .{};
    var commands: [0]draw.Command = .{};
    var tracked: [2]ids.Id = undefined;
    var storage: [16]u8 = undefined;
    var editor = try text_edit.Buffer.init(&storage, "A");
    var scroll: f32 = 0;
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    try ctx.setInteractionIdStorage(&tracked);
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 200, .y = 100 } });
    try ctx.requestFocus(7);
    const region: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 200, .max_y = 100 };
    const rect: layout.Rect = .{ .x = 10, .y = 10, .width = 120, .height = 24 };
    const events = [_]input_events.Event{.{ .text = 'B' }};
    try t.expectEqual(Context.TextRenderFailurePolicy.retain_edits, Context.text_render_failure_policy);
    try t.expectError(error.OutOfCapacity, ctx.inputTextScrolled(7, rect, &editor, &events, false, f, 1, 0xffffffff, region, &scroll));
    try t.expectEqualStrings("AB", editor.view());
    try t.expectEqual(@as(usize, 2), editor.cursor);
    try t.expectEqual(@as(f32, 0), scroll);
    try t.expectEqual(@as(usize, 0), ctx.interaction_state.visited_count);
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.vertex_count);
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.index_count);
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.command_count);
    try ctx.endFrame();
    try ctx.releaseFrame();
}

// The tracked visual API must expose consumed events even when geometry fails.
test "stage28_24 tracked render failure reports consumed events" {
    const t = std.testing;
    const glyphs = [_]font.Glyph{.{ .codepoint = 63, .advance_x = 8, .bearing_x = 0, .bearing_y = 8, .width = 6, .height = 9, .u0 = 0, .v0 = 0, .u1 = 1, .v1 = 1 }};
    const f: font.Font = .{ .glyphs = &glyphs, .texture = 42, .ascent = 9, .descent = -3, .line_gap = 2, .fallback = 63 };
    var vertices: [0]draw.Vertex = .{};
    var indices: [0]u32 = .{};
    var commands: [0]draw.Command = .{};
    var tracked: [2]ids.Id = undefined;
    var storage: [16]u8 = undefined;
    var editor = try text_edit.Buffer.init(&storage, "A");
    var scroll: f32 = 0;
    var anchor: ?usize = null;
    var progress: text_input.Progress = .{};
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    try ctx.setInteractionIdStorage(&tracked);
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 200, .y = 100 } });
    try ctx.requestFocus(7);
    const clip_rect: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 200, .max_y = 100 };
    const rect: layout.Rect = .{ .x = 10, .y = 10, .width = 120, .height = 24 };
    const events = [_]input_events.Event{ .{ .text = 'B' }, .{ .text = 'C' } };
    try t.expectError(error.OutOfCapacity, ctx.inputTextDraggedTracked(7, rect, &editor, &events, false, f, 1, 0xffffffff, clip_rect, &scroll, &anchor, &progress));
    try t.expectEqual(@as(usize, 2), progress.consumed);
    try t.expectEqual(@as(usize, 2), progress.changes);
    try t.expect(progress.focused);
    try t.expectEqualStrings("ABC", editor.view());
    try t.expectEqual(@as(f32, 0), scroll);
    try t.expectEqual(@as(usize, 0), ctx.interaction_state.visited_count);
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.vertex_count);
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.index_count);
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.command_count);
    try ctx.endFrame();
    try ctx.releaseFrame();
}

test "stage28_24 tracked edit failure supports next frame suffix" {
    const t = std.testing;
    const glyphs = [_]font.Glyph{.{ .codepoint = 63, .advance_x = 8, .bearing_x = 0, .bearing_y = 8, .width = 6, .height = 9, .u0 = 0, .v0 = 0, .u1 = 1, .v1 = 1 }};
    const f: font.Font = .{ .glyphs = &glyphs, .texture = 42, .ascent = 9, .descent = -3, .line_gap = 2, .fallback = 63 };
    var vertices: [64]draw.Vertex = undefined;
    var indices: [96]u32 = undefined;
    var commands: [16]draw.Command = undefined;
    var tracked: [2]ids.Id = undefined;
    var storage: [2]u8 = undefined;
    var editor = try text_edit.Buffer.init(&storage, "A");
    var scroll: f32 = 0;
    var anchor: ?usize = null;
    var progress: text_input.Progress = .{};
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    try ctx.setInteractionIdStorage(&tracked);
    const clip_rect: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 200, .max_y = 100 };
    const rect: layout.Rect = .{ .x = 10, .y = 10, .width = 120, .height = 24 };
    const events = [_]input_events.Event{
        .{ .text = 'B' },
        .{ .text = 'C' },
        .{ .key = .{ .code = text_input.Keys.left, .down = true } },
    };
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 200, .y = 100 } });
    try ctx.requestFocus(7);
    try t.expectError(error.OutOfCapacity, ctx.inputTextDraggedTracked(7, rect, &editor, &events, false, f, 1, 0xffffffff, clip_rect, &scroll, &anchor, &progress));
    try t.expectEqual(@as(usize, 1), progress.consumed);
    try t.expectEqual(@as(usize, 1), progress.changes);
    try t.expectEqualStrings("AB", editor.view());
    try t.expectEqual(@as(usize, 2), editor.cursor);
    try t.expectEqual(@as(usize, 0), ctx.interaction_state.visited_count);
    try ctx.endFrame();
    try ctx.releaseFrame();

    // The engine explicitly drops the failed insertion and submits only the
    // unconsumed movement event. It MUST NOT replay the successful 'B'.
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 200, .y = 100 } });
    try ctx.requestFocus(7);
    const remaining = events[2..];
    try t.expectEqual(@as(usize, 0), try ctx.inputTextDraggedTracked(7, rect, &editor, remaining, progress.shift, f, 1, 0xffffffff, clip_rect, &scroll, &anchor, &progress));
    try t.expectEqual(@as(usize, 1), progress.consumed);
    try t.expectEqual(@as(usize, 0), progress.changes);
    try t.expectEqualStrings("AB", editor.view());
    try t.expectEqual(@as(usize, 1), editor.cursor);
    try ctx.endFrame();
    try ctx.releaseFrame();
}

// A render failure after interaction rollback must not leave a stale drag
// anchor that could be mistaken for an active capture on a later frame.
test "stage28_26 render failure invalidates caller drag anchor" {
    const t = std.testing;
    const glyphs = [_]font.Glyph{.{ .codepoint = 63, .advance_x = 8, .bearing_x = 0, .bearing_y = 8, .width = 6, .height = 9, .u0 = 0, .v0 = 0, .u1 = 1, .v1 = 1 }};
    const f: font.Font = .{ .glyphs = &glyphs, .texture = 42, .ascent = 9, .descent = -3, .line_gap = 2, .fallback = 63 };
    var vertices: [0]draw.Vertex = .{};
    var indices: [0]u32 = .{};
    var commands: [0]draw.Command = .{};
    var tracked: [2]ids.Id = undefined;
    var storage: [8]u8 = undefined;
    var editor = try text_edit.Buffer.init(&storage, "A");
    var scroll: f32 = 0;
    var anchor: ?usize = 0;
    var progress: text_input.Progress = .{};
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    try ctx.setInteractionIdStorage(&tracked);
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 200, .y = 100 } });
    try ctx.requestFocus(7);
    const clip_rect: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 200, .max_y = 100 };
    const rect: layout.Rect = .{ .x = 10, .y = 10, .width = 120, .height = 24 };
    const events = [_]input_events.Event{.{ .text = 'B' }};
    try t.expectError(error.OutOfCapacity, ctx.inputTextDraggedTracked(7, rect, &editor, &events, false, f, 1, 0xffffffff, clip_rect, &scroll, &anchor, &progress));
    try t.expectEqual(@as(?usize, null), anchor);
    try t.expectEqualStrings("AB", editor.view());
    try t.expectEqual(@as(usize, 1), progress.consumed);
    try t.expectEqual(@as(f32, 0), scroll);
    try t.expectEqual(@as(usize, 0), ctx.interaction_state.visited_count);
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.vertex_count);
    try ctx.endFrame();
    try ctx.releaseFrame();
}

// Externally corrupted UTF-8 is rejected before interaction or event replay.
// The caller can repair its storage and retry without losing the drag anchor.
test "stage28_27 tracked preflight rejects invalid UTF-8 without consuming events" {
    const t = std.testing;
    const glyphs = [_]font.Glyph{.{ .codepoint = 63, .advance_x = 8, .bearing_x = 0, .bearing_y = 8, .width = 6, .height = 9, .u0 = 0, .v0 = 0, .u1 = 1, .v1 = 1 }};
    const f: font.Font = .{ .glyphs = &glyphs, .texture = 42, .ascent = 9, .descent = -3, .line_gap = 2, .fallback = 63 };
    var vertices: [16]draw.Vertex = undefined;
    var indices: [24]u32 = undefined;
    var commands: [4]draw.Command = undefined;
    var tracked: [2]ids.Id = undefined;
    var storage: [8]u8 = undefined;
    var editor = try text_edit.Buffer.init(&storage, "A");
    storage[0] = 0xff; // External corruption; len and cursor are still in range.
    var scroll: f32 = 0;
    var anchor: ?usize = 0;
    var progress: text_input.Progress = .{ .consumed = 99, .changes = 99 };
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    try ctx.setInteractionIdStorage(&tracked);
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 200, .y = 100 } });
    try ctx.requestFocus(7);
    const clip_rect: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 200, .max_y = 100 };
    const rect: layout.Rect = .{ .x = 10, .y = 10, .width = 120, .height = 24 };
    const events = [_]input_events.Event{.{ .text = 'B' }};
    try t.expectError(error.InvalidUtf8, ctx.inputTextDraggedTracked(7, rect, &editor, &events, false, f, 1, 0xffffffff, clip_rect, &scroll, &anchor, &progress));
    try t.expectEqual(@as(u8, 0xff), storage[0]);
    try t.expectEqual(@as(usize, 1), editor.len);
    try t.expectEqual(@as(usize, 1), editor.cursor);
    try t.expectEqual(@as(?usize, 0), anchor);
    try t.expectEqual(@as(f32, 0), scroll);
    try t.expectEqual(@as(usize, 0), progress.consumed);
    try t.expectEqual(@as(usize, 0), progress.changes);
    try t.expectEqual(@as(usize, 0), ctx.interaction_state.visited_count);
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.vertex_count);
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.index_count);
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.command_count);
    try ctx.endFrame();
    try ctx.releaseFrame();
}

// Preflight errors must not claim a widget ID, emit geometry, consume input,
// or mutate the editor. The progress output is deterministic even on failure.
test "stage28_25 tracked preflight rejects invalid scroll without side effects" {
    const t = std.testing;
    const glyphs = [_]font.Glyph{.{ .codepoint = 63, .advance_x = 8, .bearing_x = 0, .bearing_y = 8, .width = 6, .height = 9, .u0 = 0, .v0 = 0, .u1 = 1, .v1 = 1 }};
    const f: font.Font = .{ .glyphs = &glyphs, .texture = 42, .ascent = 9, .descent = -3, .line_gap = 2, .fallback = 63 };
    var vertices: [16]draw.Vertex = undefined;
    var indices: [24]u32 = undefined;
    var commands: [4]draw.Command = undefined;
    var tracked: [2]ids.Id = undefined;
    var storage: [8]u8 = undefined;
    var editor = try text_edit.Buffer.init(&storage, "A");
    var scroll: f32 = -1;
    var anchor: ?usize = 0;
    var progress: text_input.Progress = .{ .consumed = 99, .changes = 99, .shift = false, .focused = true };
    var ctx: Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    try ctx.setInteractionIdStorage(&tracked);
    try ctx.beginFrame(.{ .delta_seconds = 0.016, .display_size = .{ .x = 200, .y = 100 } });
    try ctx.requestFocus(7);
    const clip_rect: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 200, .max_y = 100 };
    const rect: layout.Rect = .{ .x = 10, .y = 10, .width = 120, .height = 24 };
    const events = [_]input_events.Event{.{ .text = 'B' }};
    try t.expectError(error.InvalidPosition, ctx.inputTextDraggedTracked(7, rect, &editor, &events, true, f, 1, 0xffffffff, clip_rect, &scroll, &anchor, &progress));
    try t.expectEqualStrings("A", editor.view());
    try t.expectEqual(@as(usize, 1), editor.cursor);
    try t.expectEqual(@as(f32, -1), scroll);
    try t.expectEqual(@as(?usize, 0), anchor);
    try t.expectEqual(@as(usize, 0), progress.consumed);
    try t.expectEqual(@as(usize, 0), progress.changes);
    try t.expect(progress.shift);
    try t.expect(!progress.focused);
    try t.expectEqual(@as(usize, 0), ctx.interaction_state.visited_count);
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.vertex_count);
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.index_count);
    try t.expectEqual(@as(usize, 0), ctx.geometry.?.command_count);
    try ctx.endFrame();
    try ctx.releaseFrame();
}

// Explicitly include every subsystem's tests in `zig build test`.
// Public module exports alone do not document the intended test coverage.
test "all NitroUI subsystem tests are reachable" {
    _ = @import("memory.zig");
    _ = @import("input.zig");
    _ = @import("ids.zig");
    _ = @import("state.zig");
    _ = @import("draw.zig");
    _ = @import("clip.zig");
    _ = @import("layout.zig");
    _ = @import("interaction.zig");
    _ = @import("style.zig");
    _ = @import("font.zig");
    _ = @import("text.zig");
    _ = @import("text_edit.zig");
    _ = @import("text_input.zig");
}
