//! Single-pointer, primary-button interaction state for immediate-mode widgets.
//! Widgets must be submitted in deterministic order after input batches are processed.
const std = @import("std");
const input = @import("input.zig");
const layout = @import("layout.zig");
const ids = @import("ids.zig");

pub const Error = error{ InvalidRect, InvalidFrameState, DuplicateId, IdTrackingCapacity, NavigationCapacity };
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
    /// Keyboard focus persists only while the widget is submitted each frame.
    focused_id: ?ids.Id = null,
    focus_seen: bool = false,
    hovered_id: ?ids.Id = null,
    active_seen: bool = false,
    frame_open: bool = false,
    /// Optional engine-owned diagnostic storage. When absent, only hovered/active
    /// duplicates are detected, preserving the original constant-memory path.
    visited_ids: ?[]ids.Id = null,
    visited_count: usize = 0,
    /// Caller-owned, disjoint arrays; previous order is retained between frames.
    navigation_previous: ?[]ids.Id = null,
    navigation_current: ?[]ids.Id = null,
    navigation_count: usize = 0,
    previous_count: usize = 0,
    navigation_resolved: bool = false,
    navigation_tab_requested: bool = false,
    navigation_reverse: bool = false,
    // Previous-order Tab target retained if the current frame disables it.
    navigation_stale_target: ?ids.Id = null,

    /// Configure only outside an open frame. Storage must outlive this State.
    pub fn setIdTrackingStorage(self: *State, storage: ?[]ids.Id) Error!void {
        if (self.frame_open) return error.InvalidFrameState;
        self.visited_ids = storage;
        self.visited_count = 0;
    }

    /// Both slices must be disjoint and remain valid until detached.
    pub fn setNavigationStorage(self: *State, previous: ?[]ids.Id, current: ?[]ids.Id) Error!void {
        if (self.frame_open) return error.InvalidFrameState;
        if ((previous == null) != (current == null)) return error.NavigationCapacity;
        if (previous) |p| {
            const c = current.?;
            if (p.len == 0 or c.len == 0) return error.NavigationCapacity;
            // Both arrays are written during frame finalization. Reject aliasing,
            // including partially overlapping subslices of the same allocation.
            const element_size = @sizeOf(ids.Id);
            const p_bytes = std.math.mul(usize, p.len, element_size) catch return error.NavigationCapacity;
            const c_bytes = std.math.mul(usize, c.len, element_size) catch return error.NavigationCapacity;
            const p_start = @intFromPtr(p.ptr);
            const c_start = @intFromPtr(c.ptr);
            const p_end = std.math.add(usize, p_start, p_bytes) catch return error.NavigationCapacity;
            const c_end = std.math.add(usize, c_start, c_bytes) catch return error.NavigationCapacity;
            if (p_start < c_end and c_start < p_end) return error.NavigationCapacity;
        }
        self.navigation_previous = previous;
        self.navigation_current = current;
        self.previous_count = 0;
        self.navigation_count = 0;
    }

    pub fn beginFrame(self: *State) void {
        self.visited_count = 0;
        self.hovered_id = null;
        self.active_seen = false;
        self.focus_seen = false;
        self.navigation_count = 0;
        self.navigation_resolved = false;
        self.navigation_tab_requested = false;
        self.navigation_reverse = false;
        self.navigation_stale_target = null;
        self.frame_open = true;
    }

    /// Explicit focus request; caller must submit the same ID in this frame.
    /// No allocations; duplicate-ID diagnostics remain in item().
    pub fn requestFocus(self: *State, id: ids.Id) Error!void {
        if (!self.frame_open) return error.InvalidFrameState;
        self.focused_id = id;
        self.focus_seen = false;
    }

    /// One-shot keyboard activation for an already submitted focused item.
    /// Only button-like widgets should call this method. Key repeats do not
    /// produce repeated clicks; pointer and keyboard activations coalesce.
    pub fn keyboardActivate(self: *const State, id: ids.Id, snapshot: input.Snapshot) Error!bool {
        if (!self.frame_open) return error.InvalidFrameState;
        return snapshot.focused and self.focus_seen and
            self.focused_id != null and self.focused_id.? == id and
            (snapshot.keyPressed(input.NavigationKey.enter) or
                snapshot.keyPressed(input.NavigationKey.space));
    }

    /// Call after input processing. Rectangles are half-open [x,x+w) × [y,y+h).
    /// Input is a frame snapshot; press and release within one frame may both
    /// be true, in which case a click can be generated immediately.
    pub fn item(self: *State, id: ids.Id, rect: layout.Rect, snapshot: input.Snapshot) Error!Result {
        return self.itemEnabled(id, rect, snapshot, true);
    }

    /// Submit a widget with explicit eligibility. Disabled items still participate
    /// in optional duplicate-ID diagnostics, but cannot receive focus, pointer
    /// capture, or enter the keyboard navigation order.
    pub fn itemEnabled(self: *State, id: ids.Id, rect: layout.Rect, snapshot: input.Snapshot, enabled: bool) Error!Result {
        if (!self.frame_open) return error.InvalidFrameState;
        if (!valid(rect)) return error.InvalidRect;
        if (self.hovered_id != null and self.hovered_id.? == id) return error.DuplicateId;
        if (self.active_id != null and self.active_id.? == id and self.active_seen) return error.DuplicateId;
        // Capacity errors must not register the ID, resolve Tab, or change focus.
        // Check before mutating optional ID-tracking storage.
        if (self.navigation_current) |current| {
            if (self.navigation_count > current.len) return error.NavigationCapacity;
            // Navigation storage is also a complete per-frame ID list. Reject
            // duplicates even when optional diagnostic ID tracking is disabled.
            for (current[0..self.navigation_count]) |submitted| {
                if (submitted == id) return error.DuplicateId;
            }
            if (enabled and self.navigation_count == current.len) return error.NavigationCapacity;
            if (self.navigation_previous) |previous| {
                // endFrame copies all submitted IDs into previous. Fail before
                // registering the item if that destination cannot hold it.
                if ((enabled and self.navigation_count >= previous.len) or self.previous_count > previous.len)
                    return error.NavigationCapacity;
            } else return error.NavigationCapacity;
        }
        // Validate previous-order metadata before any diagnostic storage mutation.
        if (self.navigation_previous) |previous| {
            if (self.previous_count > previous.len) return error.NavigationCapacity;
        }
        if (self.visited_ids) |storage| {
            if (self.visited_count > storage.len) return error.IdTrackingCapacity;
            for (storage[0..self.visited_count]) |previous| {
                if (previous == id) return error.DuplicateId;
            }
            if (self.visited_count == storage.len) return error.IdTrackingCapacity;
            storage[self.visited_count] = id;
            self.visited_count += 1;
        }

        // Resolve Tab once using last frame's submission order. This makes
        // navigation independent of the current frame's partial widget list.
        if (!self.navigation_resolved) {
            self.navigation_resolved = true;
            if (snapshot.focused and snapshot.keyPressed(input.NavigationKey.tab)) {
                self.navigation_tab_requested = true;
                self.navigation_reverse = snapshot.keyDown(input.NavigationKey.shift);
                if (self.navigation_previous) |previous| {
                    if (self.previous_count > previous.len) return error.NavigationCapacity;
                    if (self.previous_count != 0) {
                        const reverse = snapshot.keyDown(input.NavigationKey.shift);
                        var target: usize = if (reverse) self.previous_count - 1 else 0;
                        if (self.focused_id) |focused| {
                            for (previous[0..self.previous_count], 0..) |candidate, i| {
                                if (candidate == focused) {
                                    target = if (reverse)
                                        (if (i == 0) self.previous_count - 1 else i - 1)
                                    else
                                        (if (i + 1 == self.previous_count) 0 else i + 1);
                                    break;
                                }
                            }
                        }
                        self.focused_id = previous[target];
                        self.navigation_stale_target = previous[target];
                        self.focus_seen = false;
                    }
                }
            }
        }
        if (!enabled) {
            if (self.focused_id != null and self.focused_id.? == id) {
                self.focused_id = null;
                self.focus_seen = false;
            }
            if (self.active_id != null and self.active_id.? == id) {
                self.active_id = null;
                self.active_seen = false;
            }
            return .{};
        }
        if (self.navigation_current) |current| {
            current[self.navigation_count] = id;
            self.navigation_count += 1;
        }

        const inside = snapshot.focused and snapshot.pointer_x >= rect.x and
            snapshot.pointer_x < rect.x + rect.width and snapshot.pointer_y >= rect.y and
            snapshot.pointer_y < rect.y + rect.height;
        const hovered = inside and (self.hovered_id == null or self.hovered_id.? == id);
        if (hovered) self.hovered_id = id;

        if (self.active_id != null and self.active_id.? == id) self.active_seen = true;
        if (self.focused_id != null and self.focused_id.? == id) self.focus_seen = true;
        var result: Result = .{ .hovered = hovered };
        if (!snapshot.focused) {
            self.focused_id = null;
            if (self.active_id != null and self.active_id.? == id) self.active_id = null;
            return result;
        }
        if (self.active_id == null and hovered and snapshot.primary_pressed) {
            self.active_id = id;
            self.focused_id = id;
            self.focus_seen = true;
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
        if (!snapshot.focused) {
            self.focused_id = null;
        } else if (!self.focus_seen) {
            // A stale Tab target is resolved against the completed eligible order.
            // Prefer the nearest surviving successor/predecessor in the previous
            // order, wrapping once. Newly introduced items are the fallback.
            if (self.navigation_tab_requested and self.navigation_count != 0) {
                const current = self.navigation_current orelse return error.NavigationCapacity;
                if (self.navigation_count > current.len) return error.NavigationCapacity;
                const previous = self.navigation_previous orelse return error.NavigationCapacity;
                if (self.previous_count > previous.len) return error.NavigationCapacity;
                var replacement: ?ids.Id = null;
                if (self.navigation_stale_target) |stale| {
                    var stale_index: ?usize = null;
                    for (previous[0..self.previous_count], 0..) |candidate, i| {
                        if (candidate == stale) {
                            stale_index = i;
                            break;
                        }
                    }
                    if (stale_index) |index| {
                        var offset: usize = 1;
                        while (offset < self.previous_count) : (offset += 1) {
                            const candidate_index = if (self.navigation_reverse)
                                (if (index >= offset) index - offset else self.previous_count - (offset - index))
                            else
                                (if (offset < self.previous_count - index) index + offset else offset - (self.previous_count - index));
                            const candidate = previous[candidate_index];
                            for (current[0..self.navigation_count]) |eligible| {
                                if (candidate == eligible) {
                                    replacement = candidate;
                                    break;
                                }
                            }
                            if (replacement != null) break;
                        }
                    }
                }
                self.focused_id = replacement orelse current[if (self.navigation_reverse) self.navigation_count - 1 else 0];
            } else {
                self.focused_id = null;
            }
        }
        if (self.navigation_previous) |previous| {
            const current = self.navigation_current orelse return error.NavigationCapacity;
            if (self.navigation_count > current.len or self.navigation_count > previous.len)
                return error.NavigationCapacity;
            @memcpy(previous[0..self.navigation_count], current[0..self.navigation_count]);
            self.previous_count = self.navigation_count;
        }
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

test "focus request, persistence, missing widget cleanup and frame contract" {
    const t = std.testing;
    var state: State = .{};
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 20, .height = 20 };
    const outside: input.Snapshot = .{ .pointer_x = 50, .pointer_y = 50 };
    try t.expectError(error.InvalidFrameState, state.requestFocus(17));
    state.beginFrame();
    try state.requestFocus(17);
    _ = try state.item(17, rect, outside);
    try state.endFrame(outside);
    try t.expectEqual(@as(?ids.Id, 17), state.focused_id);
    state.beginFrame();
    _ = try state.item(17, rect, outside);
    try state.endFrame(outside);
    try t.expectEqual(@as(?ids.Id, 17), state.focused_id);
    state.beginFrame();
    try state.endFrame(outside);
    try t.expectEqual(@as(?ids.Id, null), state.focused_id);
}

test "pointer press focuses and window focus loss clears" {
    const t = std.testing;
    var state: State = .{};
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 20, .height = 20 };
    const pressed: input.Snapshot = .{ .pointer_x = 5, .pointer_y = 5, .primary_pressed = true, .buttons_down = 1 };
    state.beginFrame();
    _ = try state.item(9, rect, pressed);
    try t.expectEqual(@as(?ids.Id, 9), state.focused_id);
    try state.endFrame(pressed);
    state.beginFrame();
    const lost: input.Snapshot = .{ .focused = false };
    _ = try state.item(9, rect, lost);
    try state.endFrame(lost);
    try t.expectEqual(@as(?ids.Id, null), state.focused_id);
}

test "stage28_1 focused keyboard activation is one-shot and focus-scoped" {
    const t = std.testing;
    var state: State = .{};
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 20, .height = 20 };
    var processor: input.Processor = .{};
    try t.expectError(error.InvalidFrameState, state.keyboardActivate(4, processor.snapshot));
    state.beginFrame();
    try state.requestFocus(4);
    try processor.process(&.{.{ .key = .{ .code = input.NavigationKey.enter, .down = true } }});
    try t.expect(!(try state.keyboardActivate(4, processor.snapshot))); // Not submitted yet.
    _ = try state.item(4, rect, processor.snapshot);
    try t.expect(try state.keyboardActivate(4, processor.snapshot));
    try t.expect(!(try state.keyboardActivate(5, processor.snapshot)));
    try state.endFrame(processor.snapshot);
    processor.beginFrame();
    state.beginFrame();
    _ = try state.item(4, rect, processor.snapshot);
    try t.expect(!(try state.keyboardActivate(4, processor.snapshot)));
    try state.endFrame(processor.snapshot);
    processor.beginFrame();
    state.beginFrame();
    try processor.process(&.{.{ .focus = false }});
    _ = try state.item(4, rect, processor.snapshot);
    try t.expect(!(try state.keyboardActivate(4, processor.snapshot)));
    try state.endFrame(processor.snapshot);
}

test "stage28_2 tab and shift tab wrap previous-frame order" {
    const t = std.testing;
    var state: State = .{};
    var previous: [3]ids.Id = undefined;
    var current: [3]ids.Id = undefined;
    try state.setNavigationStorage(&previous, &current);
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 };
    const away: input.Snapshot = .{ .pointer_x = 100, .pointer_y = 100 };
    state.beginFrame();
    _ = try state.item(10, rect, away);
    _ = try state.item(20, rect, away);
    _ = try state.item(30, rect, away);
    try state.endFrame(away);
    var snapshot: input.Snapshot = away;
    snapshot.keys_pressed[1] = 0b10; // Tab (key 9)
    state.beginFrame();
    _ = try state.item(10, rect, snapshot);
    _ = try state.item(20, rect, snapshot);
    _ = try state.item(30, rect, snapshot);
    try t.expectEqual(@as(?ids.Id, 10), state.focused_id);
    try state.endFrame(snapshot);
    state.beginFrame();
    _ = try state.item(10, rect, snapshot);
    _ = try state.item(20, rect, snapshot);
    _ = try state.item(30, rect, snapshot);
    try t.expectEqual(@as(?ids.Id, 20), state.focused_id);
    try state.endFrame(snapshot);
    snapshot.keys_down[2] = 1; // Shift (key 16)
    state.beginFrame();
    _ = try state.item(10, rect, snapshot);
    _ = try state.item(20, rect, snapshot);
    _ = try state.item(30, rect, snapshot);
    try t.expectEqual(@as(?ids.Id, 10), state.focused_id);
    try state.endFrame(snapshot);
}

test "stage28_3 navigation capacity failure is atomic with ID tracking and focus" {
    const t = std.testing;
    var state: State = .{};
    var previous: [1]ids.Id = undefined;
    var current: [1]ids.Id = undefined;
    var visited: [2]ids.Id = undefined;
    try state.setNavigationStorage(&previous, &current);
    try state.setIdTrackingStorage(&visited);
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 5, .height = 5 };
    const away: input.Snapshot = .{ .pointer_x = 100, .pointer_y = 100 };

    state.beginFrame();
    _ = try state.item(1, rect, away);
    try t.expectEqual(@as(usize, 1), state.navigation_count);
    try t.expectEqual(@as(usize, 1), state.visited_count);
    try t.expectError(error.NavigationCapacity, state.item(2, rect, away));
    try t.expectEqual(@as(usize, 1), state.navigation_count);
    try t.expectEqual(@as(usize, 1), state.visited_count);
    try t.expectEqual(@as(?ids.Id, null), state.focused_id);
    try state.endFrame(away);

    // The rejected ID is eligible on the next frame; no phantom duplicate.
    state.beginFrame();
    _ = try state.item(2, rect, away);
    try t.expectEqual(@as(usize, 1), state.visited_count);
    try state.endFrame(away);
}

test "stage28_3 navigation preflight rejects corrupt previous count without mutation" {
    const t = std.testing;
    var state: State = .{};
    var previous: [1]ids.Id = undefined;
    var current: [1]ids.Id = undefined;
    var visited: [1]ids.Id = undefined;
    try state.setNavigationStorage(&previous, &current);
    try state.setIdTrackingStorage(&visited);
    state.beginFrame();
    state.previous_count = 2;
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 5, .height = 5 };
    try t.expectError(error.NavigationCapacity, state.item(3, rect, .{}));
    try t.expectEqual(@as(usize, 0), state.visited_count);
    try t.expectEqual(@as(usize, 0), state.navigation_count);
    try t.expect(!state.navigation_resolved);
    state.previous_count = 0;
    _ = try state.item(3, rect, .{});
    try state.endFrame(.{});
}

test "stage28_4 navigation storage rejects overlap and retains configuration" {
    const t = std.testing;
    var state: State = .{};
    var storage: [6]ids.Id = undefined;
    try t.expectError(error.NavigationCapacity, state.setNavigationStorage(storage[0..3], storage[2..5]));
    try t.expect(state.navigation_previous == null and state.navigation_current == null);
    try t.expectError(error.NavigationCapacity, state.setNavigationStorage(storage[0..3], storage[0..3]));
    try state.setNavigationStorage(storage[0..3], storage[3..6]);
    try t.expectEqual(@as(usize, 0), state.previous_count);
}

test "stage28_4 previous storage capacity checked before widget registration" {
    const t = std.testing;
    var state: State = .{};
    var previous: [1]ids.Id = undefined;
    var current: [3]ids.Id = undefined;
    var visited: [3]ids.Id = undefined;
    try state.setNavigationStorage(&previous, &current);
    try state.setIdTrackingStorage(&visited);
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 5, .height = 5 };
    const away: input.Snapshot = .{ .pointer_x = 100, .pointer_y = 100 };
    state.beginFrame();
    _ = try state.item(10, rect, away);
    try t.expectError(error.NavigationCapacity, state.item(20, rect, away));
    try t.expectEqual(@as(usize, 1), state.visited_count);
    try t.expectEqual(@as(usize, 1), state.navigation_count);
    try state.endFrame(away);
    try t.expectEqual(@as(usize, 1), state.previous_count);
    try t.expectEqual(@as(ids.Id, 10), previous[0]);
}

test "stage28_4 disappearing focused widget clears focus" {
    const t = std.testing;
    var state: State = .{};
    var previous: [2]ids.Id = undefined;
    var current: [2]ids.Id = undefined;
    try state.setNavigationStorage(&previous, &current);
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 5, .height = 5 };
    const away: input.Snapshot = .{ .pointer_x = 100, .pointer_y = 100 };
    state.beginFrame();
    try state.requestFocus(10);
    _ = try state.item(10, rect, away);
    _ = try state.item(20, rect, away);
    try state.endFrame(away);
    try t.expectEqual(@as(?ids.Id, 10), state.focused_id);
    state.beginFrame();
    _ = try state.item(20, rect, away);
    try state.endFrame(away);
    try t.expectEqual(@as(?ids.Id, null), state.focused_id);
}

test "stage28_5 navigation rejects duplicate IDs without diagnostic storage" {
    const t = std.testing;
    var state: State = .{};
    var previous: [3]ids.Id = undefined;
    var current: [3]ids.Id = undefined;
    try state.setNavigationStorage(&previous, &current);
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 5, .height = 5 };
    const away: input.Snapshot = .{ .pointer_x = 100, .pointer_y = 100 };
    state.beginFrame();
    _ = try state.item(10, rect, away);
    _ = try state.item(20, rect, away);
    try t.expectError(error.DuplicateId, state.item(10, rect, away));
    try t.expectEqual(@as(usize, 2), state.navigation_count);
    try t.expectEqual(@as(ids.Id, 10), current[0]);
    try t.expectEqual(@as(ids.Id, 20), current[1]);
    _ = try state.item(30, rect, away);
    try state.endFrame(away);
    try t.expectEqual(@as(usize, 3), state.previous_count);
    try t.expectEqual(@as(ids.Id, 30), previous[2]);
}

test "stage28_5 corrupt current count rejected before slicing" {
    const t = std.testing;
    var state: State = .{};
    var previous: [1]ids.Id = undefined;
    var current: [1]ids.Id = undefined;
    try state.setNavigationStorage(&previous, &current);
    state.beginFrame();
    state.navigation_count = 2;
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 5, .height = 5 };
    try t.expectError(error.NavigationCapacity, state.item(10, rect, .{}));
    try t.expectEqual(@as(usize, 2), state.navigation_count);
    state.navigation_count = 0;
    _ = try state.item(10, rect, .{});
    try state.endFrame(.{});
}

test "stage28_6 disabled items are excluded from navigation and interaction" {
    const t = std.testing;
    var state: State = .{};
    var previous: [2]ids.Id = undefined;
    var current: [2]ids.Id = undefined;
    var visited: [3]ids.Id = undefined;
    try state.setNavigationStorage(&previous, &current);
    try state.setIdTrackingStorage(&visited);
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const pointer: input.Snapshot = .{ .pointer_x = 2, .pointer_y = 2, .primary_pressed = true, .buttons_down = 1 };
    state.beginFrame();
    try t.expectEqualDeep(Result{}, try state.itemEnabled(1, rect, pointer, false));
    try t.expectEqual(@as(?ids.Id, null), state.focused_id);
    try t.expectEqual(@as(usize, 0), state.navigation_count);
    try t.expectEqual(@as(usize, 1), state.visited_count);
    try t.expectError(error.DuplicateId, state.itemEnabled(1, rect, pointer, true));
    _ = try state.itemEnabled(2, rect, .{ .pointer_x = 100, .pointer_y = 100 }, true);
    try state.endFrame(.{});
    try t.expectEqual(@as(usize, 1), state.previous_count);
    try t.expectEqual(@as(ids.Id, 2), previous[0]);
}

test "stage28_6 disabling focused item clears focus without consuming navigation capacity" {
    const t = std.testing;
    var state: State = .{};
    var previous: [1]ids.Id = undefined;
    var current: [1]ids.Id = undefined;
    try state.setNavigationStorage(&previous, &current);
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const away: input.Snapshot = .{ .pointer_x = 100, .pointer_y = 100 };
    state.beginFrame();
    try state.requestFocus(5);
    _ = try state.itemEnabled(5, rect, away, false);
    try t.expectEqual(@as(?ids.Id, null), state.focused_id);
    _ = try state.itemEnabled(6, rect, away, true);
    _ = try state.itemEnabled(7, rect, away, false);
    try t.expectEqual(@as(usize, 1), state.navigation_count);
    try state.endFrame(away);
}

test "stage28_7 tab recovers when target becomes disabled" {
    const t = std.testing;
    var state: State = .{};
    var previous: [3]ids.Id = undefined;
    var current: [3]ids.Id = undefined;
    try state.setNavigationStorage(&previous, &current);
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const away: input.Snapshot = .{ .pointer_x = 100, .pointer_y = 100 };
    state.beginFrame();
    _ = try state.item(10, rect, away);
    _ = try state.item(20, rect, away);
    _ = try state.item(30, rect, away);
    try state.endFrame(away);

    var tab = away;
    tab.keys_pressed[1] = 0b10;
    state.beginFrame();
    _ = try state.itemEnabled(10, rect, tab, false);
    _ = try state.itemEnabled(20, rect, tab, true);
    _ = try state.itemEnabled(30, rect, tab, true);
    try t.expectEqual(@as(?ids.Id, null), state.focused_id);
    try state.endFrame(tab);
    try t.expectEqual(@as(?ids.Id, 20), state.focused_id);

    state.beginFrame();
    _ = try state.item(20, rect, away);
    _ = try state.item(30, rect, away);
    try state.endFrame(away);
    try t.expectEqual(@as(?ids.Id, 20), state.focused_id);
}

test "stage28_7 reverse tab recovers from disabled target" {
    const t = std.testing;
    var state: State = .{};
    var previous: [3]ids.Id = undefined;
    var current: [3]ids.Id = undefined;
    try state.setNavigationStorage(&previous, &current);
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const away: input.Snapshot = .{ .pointer_x = 100, .pointer_y = 100 };
    state.beginFrame();
    _ = try state.item(10, rect, away);
    _ = try state.item(20, rect, away);
    _ = try state.item(30, rect, away);
    try state.endFrame(away);

    var reverse = away;
    reverse.keys_pressed[1] = 0b10;
    reverse.keys_down[2] = 1;
    state.beginFrame();
    _ = try state.itemEnabled(10, rect, reverse, true);
    _ = try state.itemEnabled(20, rect, reverse, true);
    _ = try state.itemEnabled(30, rect, reverse, false);
    try state.endFrame(reverse);
    try t.expectEqual(@as(?ids.Id, 20), state.focused_id);
}

test "stage28_8 tab skips disabled middle target preserving previous order" {
    const t = std.testing;
    var state: State = .{};
    var previous: [4]ids.Id = undefined;
    var current: [4]ids.Id = undefined;
    try state.setNavigationStorage(&previous, &current);
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const away: input.Snapshot = .{ .pointer_x = 100, .pointer_y = 100 };
    state.beginFrame();
    for ([_]ids.Id{ 10, 20, 30, 40 }) |id| _ = try state.item(id, rect, away);
    try state.endFrame(away);
    state.beginFrame();
    try state.requestFocus(10);
    for ([_]ids.Id{ 10, 20, 30, 40 }) |id| _ = try state.item(id, rect, away);
    try state.endFrame(away);
    var tab = away;
    tab.keys_pressed[1] = 0b10;
    state.beginFrame();
    _ = try state.item(10, rect, tab);
    _ = try state.itemEnabled(20, rect, tab, false);
    _ = try state.item(30, rect, tab);
    _ = try state.item(40, rect, tab);
    try state.endFrame(tab);
    try t.expectEqual(@as(?ids.Id, 30), state.focused_id);
}

test "stage28_8 reverse tab skips disabled middle target" {
    const t = std.testing;
    var state: State = .{};
    var previous: [4]ids.Id = undefined;
    var current: [4]ids.Id = undefined;
    try state.setNavigationStorage(&previous, &current);
    const rect: layout.Rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const away: input.Snapshot = .{ .pointer_x = 100, .pointer_y = 100 };
    state.beginFrame();
    for ([_]ids.Id{ 10, 20, 30, 40 }) |id| _ = try state.item(id, rect, away);
    try state.endFrame(away);
    state.beginFrame();
    try state.requestFocus(40);
    for ([_]ids.Id{ 10, 20, 30, 40 }) |id| _ = try state.item(id, rect, away);
    try state.endFrame(away);
    var tab = away;
    tab.keys_pressed[1] = 0b10;
    tab.keys_down[2] = 1;
    state.beginFrame();
    _ = try state.item(10, rect, tab);
    _ = try state.item(20, rect, tab);
    _ = try state.itemEnabled(30, rect, tab, false);
    _ = try state.item(40, rect, tab);
    try state.endFrame(tab);
    try t.expectEqual(@as(?ids.Id, 20), state.focused_id);
}
