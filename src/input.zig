//! Backend-independent ordered input. Engine owns all event slices.
const std = @import("std");

pub const MouseButton = enum(u8) { primary, secondary, middle, auxiliary_1, auxiliary_2 };
/// Logical key code assigned by the engine. Supported range: 0...255.
pub const Key = u16;
pub const key_count: usize = 256;
pub const Event = union(enum) {
    pointer_move: struct { x: f32, y: f32 },
    pointer_button: struct { button: MouseButton, down: bool },
    wheel: struct { x: f32, y: f32 },
    key: struct { code: Key, down: bool, repeat: bool = false },
    text: u21,
    focus: bool,
};

pub const Error = error{ InvalidEvent, ScrollOverflow };
const KeyBits = [key_count / 8]u8;

pub const Snapshot = struct {
    pointer_x: f32 = 0,
    pointer_y: f32 = 0,
    buttons_down: u8 = 0,
    focused: bool = true,
    wheel_x: f32 = 0,
    wheel_y: f32 = 0,
    primary_pressed: bool = false,
    primary_released: bool = false,
    keys_down: KeyBits = @splat(0),
    keys_pressed: KeyBits = @splat(0),
    keys_released: KeyBits = @splat(0),

    pub fn keyDown(self: *const Snapshot, code: Key) bool {
        return bitIsSet(&self.keys_down, code);
    }
    pub fn keyPressed(self: *const Snapshot, code: Key) bool {
        return bitIsSet(&self.keys_pressed, code);
    }
    pub fn keyReleased(self: *const Snapshot, code: Key) bool {
        return bitIsSet(&self.keys_released, code);
    }
};

fn bitIsSet(bits: *const KeyBits, code: Key) bool {
    if (code >= key_count) return false;
    const index: usize = @intCast(code);
    return (bits[index / 8] & (@as(u8, 1) << @as(u3, @intCast(index % 8)))) != 0;
}

fn setBit(bits: *KeyBits, code: Key, down: bool) void {
    const index: usize = @intCast(code);
    const mask = @as(u8, 1) << @as(u3, @intCast(index % 8));
    if (down) bits[index / 8] |= mask else bits[index / 8] &= ~mask;
}

/// Continuous state persists across frames; transients accumulate within a frame.
/// `events` exposes only the most recently accepted batch, not the entire frame.
/// The engine must retain the batch storage while consumers access it.
pub const Processor = struct {
    snapshot: Snapshot = .{},
    events: []const Event = &.{},

    pub fn beginFrame(self: *Processor) void {
        self.snapshot.wheel_x = 0;
        self.snapshot.wheel_y = 0;
        self.snapshot.primary_pressed = false;
        self.snapshot.primary_released = false;
        self.snapshot.keys_pressed = @splat(0);
        self.snapshot.keys_released = @splat(0);
        self.events = &.{};
    }

    /// Transactional even if accumulated scroll becomes nonfinite.
    pub fn process(self: *Processor, events: []const Event) Error!void {
        var next = self.snapshot;
        for (events) |event| {
            switch (event) {
                .pointer_move => |p| {
                    if (!finite(p.x) or !finite(p.y)) return error.InvalidEvent;
                    next.pointer_x = p.x;
                    next.pointer_y = p.y;
                },
                .pointer_button => |b| {
                    const mask = @as(u8, 1) << @as(u3, @intCast(@backingInt(b.button)));
                    const was_down = (next.buttons_down & mask) != 0;
                    if (b.down) next.buttons_down |= mask else next.buttons_down &= ~mask;
                    if (b.button == .primary and b.down and !was_down) next.primary_pressed = true;
                    if (b.button == .primary and !b.down and was_down) next.primary_released = true;
                },
                .wheel => |w| {
                    if (!finite(w.x) or !finite(w.y)) return error.InvalidEvent;
                    next.wheel_x += w.x;
                    next.wheel_y += w.y;
                    if (!finite(next.wheel_x) or !finite(next.wheel_y)) return error.ScrollOverflow;
                },
                .key => |k| {
                    if (k.code >= key_count or (k.repeat and !k.down)) return error.InvalidEvent;
                    const was_down = next.keyDown(k.code);
                    if (k.down and !was_down) setBit(&next.keys_pressed, k.code, true);
                    if (!k.down and was_down) setBit(&next.keys_released, k.code, true);
                    setBit(&next.keys_down, k.code, k.down);
                },
                .text => |cp| {
                    if (cp > 0x10ffff or (cp >= 0xd800 and cp <= 0xdfff)) return error.InvalidEvent;
                },
                .focus => |focused| {
                    next.focused = focused;
                    if (!focused) {
                        if ((next.buttons_down & 1) != 0) next.primary_released = true;
                        next.buttons_down = 0;
                        for (&next.keys_down, 0..) |*byte, i| {
                            next.keys_released[i] |= byte.*;
                            byte.* = 0;
                        }
                    }
                },
            }
        }
        self.snapshot = next;
        self.events = events;
    }
};

fn finite(x: f32) bool {
    return std.math.isFinite(x);
}

test "transitions accumulate across batches and reset on frame boundary" {
    var p: Processor = .{};
    try p.process(&.{.{ .pointer_button = .{ .button = .primary, .down = true } }});
    try p.process(&.{.{ .pointer_button = .{ .button = .primary, .down = false } }});
    try std.testing.expect(p.snapshot.primary_pressed and p.snapshot.primary_released);
    p.beginFrame();
    try std.testing.expect(!p.snapshot.primary_pressed and !p.snapshot.primary_released);
}

test "key transitions and focus loss" {
    var p: Processor = .{};
    try p.process(&.{.{ .key = .{ .code = 42, .down = true } }});
    try std.testing.expect(p.snapshot.keyDown(42));
    try std.testing.expect(p.snapshot.keyPressed(42));
    p.beginFrame();
    try std.testing.expect(p.snapshot.keyDown(42) and !p.snapshot.keyPressed(42));
    try p.process(&.{.{ .focus = false }});
    try std.testing.expect(!p.snapshot.keyDown(42) and p.snapshot.keyReleased(42));
}

test "invalid key and scroll overflow preserve entire snapshot" {
    var p: Processor = .{};
    try std.testing.expectError(error.InvalidEvent, p.process(&.{.{ .key = .{ .code = 256, .down = true } }}));
    try std.testing.expectError(error.ScrollOverflow, p.process(&.{
        .{ .key = .{ .code = 42, .down = true } },
        .{ .wheel = .{ .x = 3.0e38, .y = 0 } },
        .{ .wheel = .{ .x = 3.0e38, .y = 0 } },
    }));
    try std.testing.expect(!p.snapshot.keyDown(42));
    try std.testing.expectEqual(@as(f32, 0), p.snapshot.wheel_x);
}

test "invalid unicode does not change state" {
    var p: Processor = .{};
    try std.testing.expectError(error.InvalidEvent, p.process(&.{.{ .text = 0xd800 }}));
    try std.testing.expectEqual(@as(usize, 0), p.events.len);
}
