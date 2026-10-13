//! Allocation-free sequential layout (vertical and horizontal). Coordinates are logical pixels.
const std = @import("std");

pub const Error = error{ InvalidRect, InvalidSize, InvalidSpacing, StackOverflow, StackUnderflow, UnbalancedStack, CoordinateOverflow, InvalidAlignment };
pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};
pub const Spacing = struct { x: f32 = 0, y: f32 = 0 };
pub const max_depth: usize = 32;

/// Flow direction within a region.
pub const Direction = enum { Vertical, Horizontal };

/// Cross-axis alignment within the region bounds.
pub const Alignment = enum { Start, Center, End };

const Region = struct {
    bounds: Rect,
    cursor_y: f32,
    cursor_x: f32,
    spacing: Spacing,
    direction: Direction,
    alignment: Alignment,
    items: usize = 0,
};

/// No ownership of external memory. A region is a vertical sequence of items.
/// `next` advances only after all inputs and coordinate arithmetic validate.
pub const Stack = struct {
    regions: [max_depth]Region = undefined,
    depth: usize = 0,

    pub fn reset(self: *Stack) void {
        self.depth = 0;
    }

    /// Push a vertical region (backward compatible).
    pub fn push(self: *Stack, bounds: Rect, spacing: Spacing) Error!void {
        try self.pushDirection(bounds, spacing, .Vertical, .Start);
    }

    /// Push a region with explicit direction and cross-axis alignment.
    pub fn pushDirection(self: *Stack, bounds: Rect, spacing: Spacing, direction: Direction, alignment: Alignment) Error!void {
        if (!valid(bounds.x) or !valid(bounds.y) or !valid(bounds.width) or !valid(bounds.height) or bounds.width < 0 or bounds.height < 0) return error.InvalidRect;
        if (!valid(spacing.x) or !valid(spacing.y) or spacing.x < 0 or spacing.y < 0) return error.InvalidSpacing;
        if (!valid(bounds.x + bounds.width) or !valid(bounds.y + bounds.height)) return error.CoordinateOverflow;
        if (self.depth >= max_depth) return error.StackOverflow;
        const cursor_x = if (direction == .Vertical) bounds.x + spacing.x else bounds.x;
        const cursor_y = if (direction == .Vertical) bounds.y else bounds.y + spacing.y;
        self.regions[self.depth] = .{
            .bounds = bounds,
            .cursor_y = cursor_y,
            .cursor_x = cursor_x,
            .spacing = spacing,
            .direction = direction,
            .alignment = alignment,
        };
        self.depth += 1;
    }

    pub fn pop(self: *Stack) Error!void {
        if (self.depth == 0) return error.StackUnderflow;
        self.depth -= 1;
    }

    /// Allocate the next slot along the region's flow axis.
    /// `size_main` is height for Vertical, width for Horizontal. `size_cross` is the
    /// orthogonal dimension (width for Vertical, height for Horizontal). If
    /// `size_cross` is null, the available cross-size minus padding is used.
    /// Cross-axis position respects `alignment`.
    pub fn next(self: *Stack, size_cross: ?f32, size_main: f32) Error!Rect {
        if (self.depth == 0 or self.depth > max_depth) return error.StackUnderflow;
        if (!valid(size_main) or size_main < 0) return error.InvalidSize;
        if (size_cross) |sc| {
            if (!valid(sc) or sc < 0) return error.InvalidSize;
        }
        const region = &self.regions[self.depth - 1];
        const cross_avail = if (region.direction == .Vertical)
            @max(@as(f32, 0), region.bounds.width - 2 * region.spacing.x)
        else
            @max(@as(f32, 0), region.bounds.height - 2 * region.spacing.y);
        const cross = size_cross orelse cross_avail;
        var x: f32 = 0;
        var y: f32 = 0;
        var w: f32 = 0;
        var h: f32 = 0;
        if (region.direction == .Vertical) {
            x = region.bounds.x + region.spacing.x + crossAlignOffset(cross, cross_avail, region.alignment);
            y = region.cursor_y + (if (region.items == 0) @as(f32, 0) else region.spacing.y);
            if (!valid(x) or !valid(y) or !valid(x + cross) or !valid(y + size_main)) return error.CoordinateOverflow;
            w = cross;
            h = size_main;
        } else {
            y = region.bounds.y + region.spacing.y + crossAlignOffset(cross, cross_avail, region.alignment);
            x = region.cursor_x + (if (region.items == 0) @as(f32, 0) else region.spacing.x);
            if (!valid(x) or !valid(y) or !valid(x + size_main) or !valid(y + cross)) return error.CoordinateOverflow;
            w = size_main;
            h = cross;
        }
        if (region.items == std.math.maxInt(usize)) return error.CoordinateOverflow;
        if (region.direction == .Vertical) {
            region.cursor_y = y + h;
        } else {
            region.cursor_x = x + w;
        }
        region.items += 1;
        return .{ .x = x, .y = y, .width = w, .height = h };
    }

    pub fn validateBalanced(self: *const Stack) Error!void {
        if (self.depth != 0) return error.UnbalancedStack;
    }
};

fn crossAlignOffset(cross: f32, avail: f32, alignment: Alignment) f32 {
    const extra = avail - cross;
    if (extra <= 0) return 0;
    return switch (alignment) {
        .Start => 0,
        .Center => extra * 0.5,
        .End => extra,
    };
}

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

test "horizontal flow advances cursor_x and places items left-to-right" {
    const t = std.testing;
    var stack: Stack = .{};
    try stack.pushDirection(.{ .x = 10, .y = 20, .width = 200, .height = 50 }, .{ .x = 5, .y = 3 }, .Horizontal, .Start);
    // horizontal: width = size_main, height = cross (or cross_avail)
    const a = try stack.next(null, 20); // width=20, height fills cross_avail=50-2*3=44
    try t.expectEqual(@as(f32, 10), a.x);
    try t.expectEqual(@as(f32, 23), a.y); // bounds.y + spacing.y
    try t.expectEqual(@as(f32, 20), a.width); // size_main
    try t.expectEqual(@as(f32, 44), a.height); // cross_avail
    const b = try stack.next(30, 20); // width=20 (size_main), height=30 (explicit cross)
    try t.expectEqual(@as(f32, 35), b.x); // 10 + 20 + 5
    try t.expectEqual(@as(f32, 23), b.y); // bounds.y + spacing.y
    try t.expectEqual(@as(f32, 20), b.width);
    try t.expectEqual(@as(f32, 30), b.height);
    const c = try stack.next(null, 20);
    try t.expectEqual(@as(f32, 60), c.x); // 35 + 20 + 5
    try stack.pop();
    try stack.validateBalanced();
}

test "horizontal alignment centers and end-aligns cross-axis" {
    const t = std.testing;
    // bounds: x=0,y=0,width=100,height=50; spacing y=10 => cross_avail=30
    var center: Stack = .{};
    try center.pushDirection(.{ .x = 0, .y = 0, .width = 100, .height = 50 }, .{ .x = 0, .y = 10 }, .Horizontal, .Center);
    const c = try center.next(20, 20); // explicit cross=20, main=20
    try t.expectEqual(@as(f32, 15), c.y); // (30 - 20) / 2 = 5 offset from bounds.y+spacing.y=10
    try center.pop();

    var end: Stack = .{};
    try end.pushDirection(.{ .x = 0, .y = 0, .width = 100, .height = 50 }, .{ .x = 0, .y = 10 }, .Horizontal, .End);
    const e = try end.next(20, 20);
    try t.expectEqual(@as(f32, 20), e.y); // base=10, offset=10 => 20
    try end.pop();

    // start is default: y = spacing.y = 10
    var start: Stack = .{};
    try start.pushDirection(.{ .x = 0, .y = 0, .width = 100, .height = 50 }, .{ .x = 0, .y = 10 }, .Horizontal, .Start);
    const s = try start.next(20, 20);
    try t.expectEqual(@as(f32, 10), s.y);
    try start.pop();
}

test "vertical alignment centers and end-aligns cross-axis" {
    const t = std.testing;
    // bounds: x=0,y=0,width=50,height=100; spacing x=10 => cross_avail=30
    var center: Stack = .{};
    try center.pushDirection(.{ .x = 0, .y = 0, .width = 50, .height = 100 }, .{ .x = 10, .y = 0 }, .Vertical, .Center);
    const c = try center.next(20, 20); // explicit cross=20, main=20
    try t.expectEqual(@as(f32, 15), c.x); // (30 - 20) / 2 = 5 offset from bounds.x+spacing.x=10
    try center.pop();

    var end: Stack = .{};
    try end.pushDirection(.{ .x = 0, .y = 0, .width = 50, .height = 100 }, .{ .x = 10, .y = 0 }, .Vertical, .End);
    const e = try end.next(20, 20);
    try t.expectEqual(@as(f32, 20), e.x); // base=10, offset=10 => 20
    try end.pop();

    var start: Stack = .{};
    try start.pushDirection(.{ .x = 0, .y = 0, .width = 50, .height = 100 }, .{ .x = 10, .y = 0 }, .Vertical, .Start);
    const s = try start.next(20, 20);
    try t.expectEqual(@as(f32, 10), s.x);
    try start.pop();
}

test "horizontal with explicit cross size and spacing" {
    const t = std.testing;
    var stack: Stack = .{};
    try stack.pushDirection(.{ .x = 5, .y = 5, .width = 100, .height = 30 }, .{ .x = 3, .y = 2 }, .Horizontal, .Start);
    const a = try stack.next(10, 20);
    try t.expectEqual(@as(f32, 5), a.x);
    try t.expectEqual(@as(f32, 7), a.y);
    try t.expectEqual(@as(f32, 20), a.width);
    try t.expectEqual(@as(f32, 10), a.height);
    const b = try stack.next(10, 20);
    try t.expectEqual(@as(f32, 28), b.x); // 5 + 20 + 3
    try t.expectEqual(@as(f32, 7), b.y);
    try stack.pop();
}

test "nested horizontal inside vertical and vice versa" {
    const t = std.testing;
    var stack: Stack = .{};
    try stack.push(.{ .x = 0, .y = 0, .width = 200, .height = 100 }, .{ .x = 5, .y = 5 });
    const row = try stack.next(null, 30);
    // vertical: first item at bounds.y = 0, spacing only between items
    try t.expectEqual(@as(f32, 5), row.x); // bounds.x + spacing.x
    try t.expectEqual(@as(f32, 0), row.y); // first item at bounds.y
    // nested horizontal row
    try stack.pushDirection(row, .{ .x = 2, .y = 2 }, .Horizontal, .Center);
    const a = try stack.next(null, 20);
    // row: x=5, y=0, w=190, h=30; horizontal sub-bounds = row
    // cross_avail = row.height - 2*spacing.y = 30 - 4 = 26
    // item height = 26 (fills cross-axis when null)
    try t.expectEqual(@as(f32, 2), a.y); // row.y + spacing.y = 0 + 2
    try t.expectEqual(@as(f32, 26), a.height);
    try stack.pop();
    const next_row = try stack.next(null, 20);
    try t.expectEqual(@as(f32, 35), next_row.y); // 0 + 30 + 5
    try stack.pop();
    try stack.validateBalanced();
}

test "horizontal overflow does not clip layout cursor" {
    const t = std.testing;
    var stack: Stack = .{};
    try stack.pushDirection(.{ .x = 0, .y = 0, .width = 50, .height = 40 }, .{ .x = 0, .y = 5 }, .Horizontal, .Start);
    const a = try stack.next(null, 20); // first item at x=0, width=20, height fills cross_avail=40-10=30
    try t.expectEqual(@as(f32, 0), a.x);
    try t.expectEqual(@as(f32, 20), a.width); // size_main
    try t.expectEqual(@as(f32, 30), a.height); // fills cross-axis
    const b = try stack.next(null, 20); // second item at x=20, width=20 (overflow in cursor_x)
    try t.expectEqual(@as(f32, 20), b.x);
    try t.expectEqual(@as(f32, 20), b.width);
    // cursor_x advanced past bounds; layout doesn't clip
    try stack.pop();
}

test "pushDirection validates direction and alignment" {
    const t = std.testing;
    var stack: Stack = .{};
    try t.expectError(error.InvalidRect, stack.pushDirection(.{ .x = 0, .y = 0, .width = -1, .height = 10 }, .{}, .Horizontal, .Start));
    try t.expectError(error.InvalidSpacing, stack.pushDirection(.{ .x = 0, .y = 0, .width = 10, .height = 10 }, .{ .x = -1, .y = 0 }, .Horizontal, .Start));
    try stack.pushDirection(.{ .x = 0, .y = 0, .width = 10, .height = 10 }, .{}, .Horizontal, .Start);
    try stack.pop();
}
