//! Single-pointer, primary-button interaction state for immediate-mode widgets.
//! Widgets must be submitted in deterministic order after input batches are processed.
const std = @import("std");
const input = @import("input.zig");
const layout = @import("layout.zig");
const ids = @import("ids.zig");

pub const Error = error{ InvalidRect, InvalidFrameState, DuplicateId, IdTrackingCapacity };
pub const Result = struct {
    hovered: bool = false,
    held: bool = false,
    pressed: bool = false,
    clicked: bool = false,
};

/// One active pointer capture at a time. The first eligible submitted widget
/// receives hover on overlap. No heap allocations or retained widget records.
pub const State = struct {
    active_id: ?ids.Id = null,
    hovered_id: ?ids.Id = null,
    active_seen: bool = false,
    frame_open: bool = false,
    /// Optional engine-owned diagnostic storage. When absent, only hovered/active
    /// duplicates are detected, preserving the original constant-memory path.
    visited_ids: ?[]ids.Id = null,
    visited_count: usize = 0,

    /// Configure only outside an open frame. Storage must outlive this State.
    pub fn setIdTrackingStorage(self: *State, storage: ?[]ids.Id) Error!void {
        if (self.frame_open) return error.InvalidFrameState;
        self.visited_ids = storage;
        self.visited_count = 0;
    }

    pub fn beginFrame(self: *State) void {
        self.visited_count = 0;
        self.hovered_id = null;
        self.active_seen = false;
        self.frame_open = true;
    }

    /// Call after input processing. Rectangles are half-open [x,x+w) × [y,y+h).
    /// Input is a frame snapshot; press and release within one frame may both
    /// be true, in which case a click can be generated immediately.
    pub fn item(self: *State, id: ids.Id, rect: layout.Rect, snapshot: input.Snapshot) Error!Result {
        if (!self.frame_open) return error.InvalidFrameState;
        if (!valid(rect)) return error.InvalidRect;
        if (self.hovered_id != null and self.hovered_id.? == id) return error.DuplicateId;
        if (self.active_id != null and self.active_id.? == id and self.active_seen) return error.DuplicateId;
        if (self.visited_ids) |storage| {
            if (self.visited_count > storage.len) return error.IdTrackingCapacity;
            for (storage[0..self.visited_count]) |previous| {
                if (previous == id) return error.DuplicateId;
            }
            if (self.visited_count == storage.len) return error.IdTrackingCapacity;
            storage[self.visited_count] = id;
            self.visited_count += 1;
        }

        const inside = snapshot.focused and snapshot.pointer_x >= rect.x and
            snapshot.pointer_x < rect.x + rect.width and snapshot.pointer_y >= rect.y and
            snapshot.pointer_y < rect.y + rect.height;
        const hovered = inside and (self.hovered_id == null or self.hovered_id.? == id);
        if (hovered) self.hovered_id = id;

        if (self.active_id != null and self.active_id.? == id) self.active_seen = true;
        var result: Result = .{ .hovered = hovered };
        if (!snapshot.focused) {
            if (self.active_id != null and self.active_id.? == id) self.active_id = null;
            return result;
        }
        if (self.active_id == null and hovered and snapshot.primary_pressed) {
            self.active_id = id;
            self.active_seen = true;
            result.pressed = true;
        }
        if (self.active_id != null and self.active_id.? == id) {
            result.held = (snapshot.buttons_down & 1) != 0;
            if (snapshot.primary_released) {
                result.clicked = hovered;
                result.held = false;
                self.active_id = null;
            }
        }
        return result;
    }

    pub fn endFrame(self: *State, snapshot: input.Snapshot) Error!void {
        if (!self.frame_open) return error.InvalidFrameState;
        // Release even if the captured widget was not submitted this frame.
        if (!snapshot.focused or snapshot.primary_released or (snapshot.buttons_down & 1) == 0)
            self.active_id = null;
        self.frame_open = false;
    }
};

fn valid(rect: layout.Rect) bool {
    return std.math.isFinite(rect.x) and std.math.isFinite(rect.y) and
        std.math.isFinite(rect.width) and std.math.isFinite(rect.height) and
        rect.width >= 0 and rect.height >= 0 and
        std.math.isFinite(rect.x + rect.width) and std.math.isFinite(rect.y + rect.height);
}

test "press, drag outside, release outside and next click" {
    const t = std.testing;
    var state: State = .{};
    var p: input.Processor = .{};
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 30, .height = 20 };
    state.beginFrame();
    try p.process(&.{ .{ .pointer_move = .{ .x = 5, .y = 5 } }, .{ .pointer_button = .{ .button = .primary, .down = true } } });
    const a = try state.item(10, rect, p.snapshot);
    try t.expect(a.hovered and a.pressed and a.held and !a.clicked);
    try state.endFrame(p.snapshot);
    p.beginFrame();
    state.beginFrame();
    try p.process(&.{.{ .pointer_move = .{ .x = 40, .y = 5 } }});
    const b = try state.item(10, rect, p.snapshot);
    try t.expect(!b.hovered and b.held);
    try state.endFrame(p.snapshot);
    p.beginFrame();
    state.beginFrame();
    try p.process(&.{.{ .pointer_button = .{ .button = .primary, .down = false } }});
    try t.expect(!(try state.item(10, rect, p.snapshot)).clicked);
    try state.endFrame(p.snapshot);
    try t.expect(state.active_id == null);
    p.beginFrame();
    state.beginFrame();
    try p.process(&.{ .{ .pointer_move = .{ .x = 5, .y = 5 } }, .{ .pointer_button = .{ .button = .primary, .down = true } }, .{ .pointer_button = .{ .button = .primary, .down = false } } });
    try t.expect((try state.item(10, rect, p.snapshot)).clicked);
    try state.endFrame(p.snapshot);
}

test "overlap prioritizes first widget, capture blocks other widget" {
    const t = std.testing;
    var state: State = .{};
    var snapshot: input.Snapshot = .{ .pointer_x = 5, .pointer_y = 5, .primary_pressed = true, .buttons_down = 1 };
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 };
    state.beginFrame();
    try t.expect((try state.item(1, rect, snapshot)).pressed);
    try t.expect(!(try state.item(2, rect, snapshot)).hovered);
    try t.expectError(error.DuplicateId, state.item(1, rect, snapshot));
    try state.endFrame(snapshot);
    state.beginFrame();
    snapshot.primary_pressed = false;
    snapshot.primary_released = true;
    snapshot.buttons_down = 0;
    try t.expect(!(try state.item(2, rect, snapshot)).clicked);
    try state.endFrame(snapshot);
    try t.expect(state.active_id == null);
}

test "invalid rectangles and focus loss" {
    const t = std.testing;
    var state: State = .{};
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 };
    try t.expectError(error.InvalidFrameState, state.item(1, rect, .{}));
    state.beginFrame();
    try t.expectError(error.InvalidRect, state.item(1, .{ .x = 0, .y = 0, .width = -1, .height = 2 }, .{}));
    _ = try state.item(1, rect, .{ .pointer_x = 2, .pointer_y = 2, .primary_pressed = true, .buttons_down = 1 });
    try state.endFrame(.{ .focused = false });
    try t.expect(state.active_id == null);
}

test "optional tracking detects non-hovered duplicates and resets per frame" {
    const t = std.testing;
    var state: State = .{};
    var storage: [2]ids.Id = undefined;
    try state.setIdTrackingStorage(&storage);
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const away: input.Snapshot = .{ .pointer_x = 100, .pointer_y = 100 };
    state.beginFrame();
    _ = try state.item(0, rect, away);
    try t.expectError(error.DuplicateId, state.item(0, rect, away));
    _ = try state.item(1, rect, away);
    try t.expectError(error.IdTrackingCapacity, state.item(2, rect, away));
    try t.expectEqual(@as(usize, 2), state.visited_count);
    try t.expectError(error.InvalidFrameState, state.setIdTrackingStorage(null));
    try state.endFrame(away);
    state.beginFrame();
    _ = try state.item(0, rect, away);
    try t.expectEqual(@as(usize, 1), state.visited_count);
    try state.endFrame(away);
}

test "stage24_8 corrupted visited count returns capacity error without trapping" {
    const t = std.testing;
    var state: State = .{};
    var storage: [2]ids.Id = undefined;
    try state.setIdTrackingStorage(&storage);
    state.beginFrame();
    state.visited_count = 3;
    try t.expectError(error.IdTrackingCapacity, state.item(9, .{ .x = 0, .y = 0, .width = 1, .height = 1 }, .{}));
    try t.expectEqual(@as(usize, 3), state.visited_count);
    try state.endFrame(.{});
}
