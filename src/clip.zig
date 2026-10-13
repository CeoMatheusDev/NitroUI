//! Hierarchical scissor rectangles in logical display coordinates.
const std = @import("std");
const draw = @import("draw.zig");

pub const Error = error{ InvalidClip, StackOverflow, StackUnderflow, UnbalancedClips };
pub const Stack = struct {
    pub const capacity: usize = 64;
    items: [capacity]draw.ClipRect = undefined,
    depth: usize = 0,

    pub fn reset(self: *Stack) void { self.depth = 0; }
    pub fn current(self: *const Stack) ?draw.ClipRect {
        if (self.depth == 0) return null;
        return self.items[self.depth - 1];
    }
    pub fn push(self: *Stack, rect: draw.ClipRect) Error!void {
        if (!valid(rect)) return error.InvalidClip;
        if (self.depth == capacity) return error.StackOverflow;
        var clipped = rect;
        if (self.current()) |parent| {
            clipped.min_x = @max(rect.min_x, parent.min_x);
            clipped.min_y = @max(rect.min_y, parent.min_y);
            clipped.max_x = @min(rect.max_x, parent.max_x);
            clipped.max_y = @min(rect.max_y, parent.max_y);
            // Empty intersections are valid and must not invert the rectangle.
            clipped.max_x = @max(clipped.max_x, clipped.min_x);
            clipped.max_y = @max(clipped.max_y, clipped.min_y);
        }
        self.items[self.depth] = clipped;
        self.depth += 1;
    }
    pub fn pop(self: *Stack) Error!void {
        if (self.depth == 0) return error.StackUnderflow;
        self.depth -= 1;
    }
    pub fn validateBalanced(self: *const Stack) Error!void {
        if (self.depth != 0) return error.UnbalancedClips;
    }
};

fn valid(rect: draw.ClipRect) bool {
    return std.math.isFinite(rect.min_x) and std.math.isFinite(rect.min_y) and
        std.math.isFinite(rect.max_x) and std.math.isFinite(rect.max_y) and
        rect.min_x <= rect.max_x and rect.min_y <= rect.max_y;
}

test "nested clips intersect and restore parent" {
    var stack: Stack = .{};
    try stack.push(.{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 });
    try stack.push(.{ .min_x = 20, .min_y = -10, .max_x = 200, .max_y = 40 });
    const inner = stack.current().?;
    try std.testing.expectEqual(@as(f32, 20), inner.min_x);
    try std.testing.expectEqual(@as(f32, 0), inner.min_y);
    try std.testing.expectEqual(@as(f32, 100), inner.max_x);
    try std.testing.expectEqual(@as(f32, 40), inner.max_y);
    try stack.pop();
    try std.testing.expectEqual(@as(f32, 100), stack.current().?.max_y);
    try stack.pop();
    try stack.validateBalanced();
}

test "disjoint rectangles produce empty clip" {
    var stack: Stack = .{};
    try stack.push(.{ .min_x = 0, .min_y = 0, .max_x = 10, .max_y = 10 });
    try stack.push(.{ .min_x = 20, .min_y = 20, .max_x = 30, .max_y = 30 });
    const r = stack.current().?;
    try std.testing.expectEqual(r.min_x, r.max_x);
    try std.testing.expectEqual(r.min_y, r.max_y);
}

test "invalid pushes are atomic and bounds are checked" {
    var stack: Stack = .{};
    try std.testing.expectError(error.StackUnderflow, stack.pop());
    try std.testing.expectError(error.InvalidClip, stack.push(.{ .min_x = 3, .min_y = 0, .max_x = 1, .max_y = 1 }));
    try std.testing.expectEqual(@as(usize, 0), stack.depth);
    const rect: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 1, .max_y = 1 };
    for (0..Stack.capacity) |_| try stack.push(rect);
    try std.testing.expectError(error.StackOverflow, stack.push(rect));
    try std.testing.expectError(error.UnbalancedClips, stack.validateBalanced());
    try std.testing.expectEqual(Stack.capacity, stack.depth);
    stack.reset();
    try stack.validateBalanced();
}
