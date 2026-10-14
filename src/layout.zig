//! Allocation-free sequential vertical layout. Coordinates are logical pixels.
const std = @import("std");

pub const Error = error{ InvalidRect, InvalidSize, InvalidSpacing, StackOverflow, StackUnderflow, UnbalancedStack, CoordinateOverflow };
pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};
pub const Spacing = struct { x: f32 = 0, y: f32 = 0 };
pub const max_depth: usize = 32;
const Region = struct { bounds: Rect, cursor_y: f32, spacing: Spacing, items: usize = 0 };

/// No ownership of external memory. A region is a vertical sequence of items.
/// `next` advances only after all inputs and coordinate arithmetic validate.
pub const Stack = struct {
    regions: [max_depth]Region = undefined,
    depth: usize = 0,

    pub fn reset(self: *Stack) void {
        self.depth = 0;
    }

    pub fn push(self: *Stack, bounds: Rect, spacing: Spacing) Error!void {
        if (!valid(bounds.x) or !valid(bounds.y) or !valid(bounds.width) or !valid(bounds.height) or bounds.width < 0 or bounds.height < 0) return error.InvalidRect;
        if (!valid(spacing.x) or !valid(spacing.y) or spacing.x < 0 or spacing.y < 0) return error.InvalidSpacing;
        if (!valid(bounds.x + bounds.width) or !valid(bounds.y + bounds.height)) return error.CoordinateOverflow;
        if (self.depth >= max_depth) return error.StackOverflow;
        self.regions[self.depth] = .{ .bounds = bounds, .cursor_y = bounds.y, .spacing = spacing };
        self.depth += 1;
    }

    pub fn pop(self: *Stack) Error!void {
        if (self.depth == 0) return error.StackUnderflow;
        self.depth -= 1;
    }

    /// Width = null uses the available inner width. Does not clip to bounds.
    /// Layout and rendering remain separate: callers choose overflow policy.
    pub fn next(self: *Stack, width: ?f32, height: f32) Error!Rect {
        if (self.depth == 0 or self.depth > max_depth) return error.StackUnderflow;
        if (!valid(height) or height < 0) return error.InvalidSize;
        if (width) |w| {
            if (!valid(w) or w < 0) return error.InvalidSize;
        }
        const region = &self.regions[self.depth - 1];
        const x = region.bounds.x + region.spacing.x;
        const available = @max(@as(f32, 0), region.bounds.width - 2 * region.spacing.x);
        const w = width orelse available;
        const y = region.cursor_y + (if (region.items == 0) @as(f32, 0) else region.spacing.y);
        const end_y = y + height;
        if (!valid(x) or !valid(available) or !valid(x + w) or !valid(y) or !valid(end_y)) return error.CoordinateOverflow;
        if (region.items == std.math.maxInt(usize)) return error.CoordinateOverflow;
        region.cursor_y = end_y;
        region.items += 1;
        return .{ .x = x, .y = y, .width = w, .height = height };
    }

    pub fn validateBalanced(self: *const Stack) Error!void {
        if (self.depth != 0) return error.UnbalancedStack;
    }
};

fn valid(value: f32) bool {
    return std.math.isFinite(value);
}

test "sequential items, nested regions and reset" {
    const t = std.testing;
    var stack: Stack = .{};
    try stack.push(.{ .x = 10, .y = 20, .width = 100, .height = 90 }, .{ .x = 5, .y = 3 });
    const a = try stack.next(null, 12);
    try t.expectEqual(@as(f32, 15), a.x);
    try t.expectEqual(@as(f32, 90), a.width);
    try t.expectEqual(@as(f32, 20), a.y);
    const b = try stack.next(25, 8);
    try t.expectEqual(@as(f32, 35), b.y);
    try stack.push(.{ .x = 20, .y = 40, .width = 40, .height = 40 }, .{});
    try t.expectEqual(@as(f32, 40), (try stack.next(null, 7)).y);
    try stack.pop();
    try t.expectEqual(@as(f32, 46), (try stack.next(null, 4)).y);
    try stack.pop();
    try stack.validateBalanced();
    stack.reset();
    try t.expectError(error.StackUnderflow, stack.next(null, 1));
}

test "invalid operations preserve layout state" {
    const t = std.testing;
    var stack: Stack = .{};
    try t.expectError(error.InvalidRect, stack.push(.{ .x = 0, .y = 0, .width = -1, .height = 1 }, .{}));
    try stack.push(.{ .x = 0, .y = 0, .width = 50, .height = 50 }, .{});
    try t.expectError(error.InvalidSize, stack.next(null, -1));
    try t.expectError(error.InvalidSize, stack.next(std.math.nan(f32), 1));
    try t.expectEqual(@as(f32, 0), (try stack.next(null, 5)).y);
    try t.expectError(error.UnbalancedStack, stack.validateBalanced());
    try stack.pop();
    try t.expectError(error.StackUnderflow, stack.pop());
}

test "stack overflow is atomic" {
    const t = std.testing;
    var stack: Stack = .{};
    for (0..max_depth) |_| try stack.push(.{ .x = 0, .y = 0, .width = 1, .height = 1 }, .{});
    try t.expectError(error.StackOverflow, stack.push(.{ .x = 0, .y = 0, .width = 1, .height = 1 }, .{}));
    try t.expectEqual(max_depth, stack.depth);
    for (0..max_depth) |_| try stack.pop();
    try stack.validateBalanced();
}

test "stage24_8 corrupted depth is rejected without trapping" {
    const t = std.testing;
    var stack: Stack = .{};
    stack.depth = max_depth + 3;
    try t.expectError(error.StackOverflow, stack.push(.{ .x = 0, .y = 0, .width = 1, .height = 1 }, .{}));
    try t.expectError(error.StackUnderflow, stack.next(null, 1));
}
