//! Allocation-free sequential vertical and horizontal layout. Coordinates are logical pixels.
const std = @import("std");
const font_mod = @import("font.zig");
const text = @import("text.zig");

pub const Error = error{ InvalidRect, InvalidSize, InvalidSpacing, StackOverflow, StackUnderflow, UnbalancedStack, CoordinateOverflow };
pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};
pub const Spacing = struct { x: f32 = 0, y: f32 = 0 };
pub const max_depth: usize = 32;
pub const Direction = enum { vertical, horizontal };
/// Cross-axis alignment within the current region.
pub const Alignment = enum { start, center, end };
const Region = struct { bounds: Rect, cursor_y: f32, cursor_x: f32, spacing: Spacing, direction: Direction = .vertical, items: usize = 0 };

/// No ownership of external memory. A region is a vertical sequence of items.
/// `next` advances only after all inputs and coordinate arithmetic validate.
pub const Stack = struct {
    regions: [max_depth]Region = undefined,
    depth: usize = 0,

    pub fn reset(self: *Stack) void {
        self.depth = 0;
    }

    pub fn push(self: *Stack, bounds: Rect, spacing: Spacing) Error!void {
        return self.pushDirection(bounds, spacing, .vertical);
    }

    /// Start a horizontal region. Widths must be explicit for predictable placement.
    pub fn pushHorizontal(self: *Stack, bounds: Rect, spacing: Spacing) Error!void {
        return self.pushDirection(bounds, spacing, .horizontal);
    }

    fn pushDirection(self: *Stack, bounds: Rect, spacing: Spacing, direction: Direction) Error!void {
        if (!valid(bounds.x) or !valid(bounds.y) or !valid(bounds.width) or !valid(bounds.height) or bounds.width < 0 or bounds.height < 0) return error.InvalidRect;
        if (!valid(spacing.x) or !valid(spacing.y) or spacing.x < 0 or spacing.y < 0) return error.InvalidSpacing;
        if (!valid(bounds.x + bounds.width) or !valid(bounds.y + bounds.height)) return error.CoordinateOverflow;
        if (self.depth >= max_depth) return error.StackOverflow;
        self.regions[self.depth] = .{ .bounds = bounds, .cursor_y = bounds.y, .cursor_x = bounds.x, .spacing = spacing, .direction = direction };
        self.depth += 1;
    }

    pub fn pop(self: *Stack) Error!void {
        if (self.depth == 0 or self.depth > max_depth) return error.StackUnderflow;
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
        const available = @max(@as(f32, 0), region.bounds.width - 2 * region.spacing.x);
        const w = width orelse (if (region.direction == .vertical) available else return error.InvalidSize);
        const x = if (region.direction == .vertical)
            region.bounds.x + region.spacing.x
        else
            region.cursor_x + (if (region.items == 0) @as(f32, 0) else region.spacing.x);
        const y = if (region.direction == .vertical)
            region.cursor_y + (if (region.items == 0) @as(f32, 0) else region.spacing.y)
        else
            region.bounds.y + region.spacing.y;
        const end_y = y + height;
        const end_x = x + w;
        if (!valid(x) or !valid(available) or !valid(end_x) or !valid(y) or !valid(end_y)) return error.CoordinateOverflow;
        if (region.items == std.math.maxInt(usize)) return error.CoordinateOverflow;
        if (region.direction == .vertical) region.cursor_y = end_y else region.cursor_x = end_x;
        region.items += 1;
        return .{ .x = x, .y = y, .width = w, .height = height };
    }

    /// Consume the remaining extent on the main axis of the current region.
    /// The cross-axis size is explicit; no implicit flex or sibling reflow occurs.
    /// Vertical: cross_size is width; horizontal: cross_size is height.
    /// A region already exceeded by previous items returns InvalidSize atomically.
    pub fn nextFillRemaining(self: *Stack, cross_size: f32) Error!Rect {
        if (self.depth == 0 or self.depth > max_depth) return error.StackUnderflow;
        if (!valid(cross_size) or cross_size < 0) return error.InvalidSize;
        const region = self.regions[self.depth - 1];
        const vertical = region.direction == .vertical;
        const spacing = if (vertical) region.spacing.y else region.spacing.x;
        const start = if (vertical) region.cursor_y else region.cursor_x;
        const bound_end = if (vertical) region.bounds.y + region.bounds.height else region.bounds.x + region.bounds.width;
        const cross_available = if (vertical)
            region.bounds.width - 2 * region.spacing.x
        else
            region.bounds.height - 2 * region.spacing.y;
        if (!valid(cross_available) or !valid(bound_end)) return error.CoordinateOverflow;
        if (cross_available < 0 or cross_size > cross_available) return error.InvalidSize;
        const offset = if (region.items == 0) @as(f32, 0) else spacing;
        const position = start + offset;
        if (!valid(position)) return error.CoordinateOverflow;
        const remaining = bound_end - position;
        if (!valid(remaining)) return error.CoordinateOverflow;
        if (remaining < 0) return error.InvalidSize;
        return if (vertical) self.next(cross_size, remaining) else self.next(remaining, cross_size);
    }

    /// Reserve a weighted share of the *currently remaining* main-axis extent.
    /// `remaining_weight` includes this item's weight and all later weighted
    /// siblings. The caller must account for later inter-item spacing itself:
    /// `future_items` is the number of items that will follow this one in the
    /// same region, including fixed-size items. No retroactive sibling reflow.
    /// Vertical: cross_size is width; horizontal: cross_size is height.
    /// For the final weighted item use weight == remaining_weight.
    pub fn nextWeighted(self: *Stack, weight: f32, remaining_weight: f32, future_items: usize, cross_size: f32) Error!Rect {
        if (self.depth == 0 or self.depth > max_depth) return error.StackUnderflow;
        if (!valid(weight) or !valid(remaining_weight) or weight <= 0 or remaining_weight <= 0 or weight > remaining_weight) return error.InvalidSize;
        if (!valid(cross_size) or cross_size < 0) return error.InvalidSize;
        const region = self.regions[self.depth - 1];
        const vertical = region.direction == .vertical;
        const spacing = if (vertical) region.spacing.y else region.spacing.x;
        const cross_available = if (vertical) region.bounds.width - 2 * region.spacing.x else region.bounds.height - 2 * region.spacing.y;
        if (!valid(cross_available)) return error.CoordinateOverflow;
        if (cross_available < 0 or cross_size > cross_available) return error.InvalidSize;
        const bound_end = if (vertical) region.bounds.y + region.bounds.height else region.bounds.x + region.bounds.width;
        const cursor = if (vertical) region.cursor_y else region.cursor_x;
        const start = cursor + (if (region.items == 0) @as(f32, 0) else spacing);
        if (!valid(bound_end) or !valid(start)) return error.CoordinateOverflow;
        const remaining = bound_end - start;
        if (!valid(remaining)) return error.CoordinateOverflow;
        if (remaining < 0) return error.InvalidSize;
        // Convert the count before multiplying, so extremely large counts
        // cannot silently wrap in integer arithmetic.
        const future: f64 = @floatFromInt(future_items);
        const reserved64 = future * @as(f64, spacing);
        if (!std.math.isFinite(reserved64) or reserved64 > @as(f64, remaining)) return error.InvalidSize;
        const distributable: f64 = @as(f64, remaining) - reserved64;
        const share64 = distributable * (@as(f64, weight) / @as(f64, remaining_weight));
        if (!std.math.isFinite(share64) or share64 < 0) return error.CoordinateOverflow;
        const share: f32 = @floatCast(share64);
        if (!valid(share)) return error.CoordinateOverflow;
        return if (vertical) self.next(cross_size, share) else self.next(share, cross_size);
    }

    /// Place an item aligned on the cross axis. Main-axis advancement is identical
    /// to `next`; alignment never changes the region's cursor or item spacing.
    /// Vertical: aligns x within the region's inner width.
    /// Horizontal: aligns y within the region's inner height.
    /// Items larger than the available cross-axis extent are rejected atomically.
    pub fn nextAligned(self: *Stack, width: ?f32, height: f32, alignment: Alignment) Error!Rect {
        if (self.depth == 0 or self.depth > max_depth) return error.StackUnderflow;
        const region = self.regions[self.depth - 1];
        if (!valid(height) or height < 0) return error.InvalidSize;
        if (width) |w| {
            if (!valid(w) or w < 0) return error.InvalidSize;
        }
        const inner_width = region.bounds.width - 2 * region.spacing.x;
        const inner_height = region.bounds.height - 2 * region.spacing.y;
        if (!valid(inner_width) or !valid(inner_height)) return error.CoordinateOverflow;
        if (inner_width < 0 or inner_height < 0) return error.InvalidSize;
        const cross_extent = if (region.direction == .vertical) (width orelse inner_width) else height;
        const cross_available = if (region.direction == .vertical) inner_width else inner_height;
        if (cross_extent > cross_available) return error.InvalidSize;
        const spare = cross_available - cross_extent;
        const offset: f32 = switch (alignment) {
            .start => 0,
            .center => spare / 2,
            .end => spare,
        };
        const rect = try self.next(width, height);
        var result = rect;
        if (region.direction == .vertical) {
            result.x = region.bounds.x + region.spacing.x + offset;
        } else {
            result.y = region.bounds.y + region.spacing.y + offset;
        }
        // All candidate coordinates are checked before returning. The input
        // bounds and offset are finite, but addition can still overflow.
        if (!valid(result.x) or !valid(result.y) or
            !valid(result.x + result.width) or !valid(result.y + result.height))
        {
            self.regions[self.depth - 1] = region;
            return error.CoordinateOverflow;
        }
        return result;
    }

    /// Reserve a single-line text rectangle using measured glyph advances and
    /// scaled font line height. The returned rectangle starts at the line top;
    /// the baseline for text.emitBaseline is (rect.x, rect.y + ascent * scale).
    /// No clipping, wrapping, or geometry emission is performed here.
    /// Invalid UTF-8, missing glyphs, and invalid dimensions do not advance the cursor.
    pub fn nextText(self: *Stack, font: font_mod.Font, utf8: []const u8, scale: f32) (Error || text.Error || font_mod.Error)!Rect {
        if (self.depth == 0 or self.depth > max_depth) return error.StackUnderflow;
        const metrics = try text.measure(font, utf8, scale);
        const height = (font.ascent - font.descent + font.line_gap) * scale;
        if (!valid(height) or height <= 0) return error.InvalidSize;
        return self.next(metrics.advance_x, height);
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

test "text layout uses font metrics and advances vertically" {
    const t = std.testing;
    const glyphs = [_]font_mod.Glyph{.{ .codepoint = 65, .advance_x = 7, .bearing_x = 0, .bearing_y = 8, .width = 6, .height = 9, .u0 = 0, .v0 = 0, .u1 = 1, .v1 = 1 }};
    const font: font_mod.Font = .{ .glyphs = &glyphs, .texture = 1, .ascent = 9, .descent = -3, .line_gap = 2 };
    var stack: Stack = .{};
    try stack.push(.{ .x = 10, .y = 20, .width = 100, .height = 100 }, .{ .x = 2, .y = 3 });
    const first = try stack.nextText(font, "AA", 2);
    try t.expectEqual(@as(f32, 12), first.x);
    try t.expectEqual(@as(f32, 20), first.y);
    try t.expectEqual(@as(f32, 28), first.width);
    try t.expectEqual(@as(f32, 28), first.height);
    try t.expectEqual(@as(f32, 38), first.y + font.ascent * 2);
    const second = try stack.nextText(font, "A", 1);
    try t.expectEqual(@as(f32, 51), second.y);
    try t.expectEqual(@as(f32, 7), second.width);
    try t.expectEqual(@as(f32, 14), second.height);
    try stack.pop();
}

test "invalid text does not consume layout space" {
    const t = std.testing;
    const glyphs = [_]font_mod.Glyph{.{ .codepoint = 65, .advance_x = 7, .bearing_x = 0, .bearing_y = 8, .width = 6, .height = 9, .u0 = 0, .v0 = 0, .u1 = 1, .v1 = 1 }};
    const font: font_mod.Font = .{ .glyphs = &glyphs, .texture = 1, .ascent = 9, .descent = -3, .line_gap = 2 };
    var stack: Stack = .{};
    try t.expectError(error.StackUnderflow, stack.nextText(font, "A", 1));
    try stack.push(.{ .x = 0, .y = 0, .width = 100, .height = 100 }, .{});
    try t.expectError(error.InvalidUtf8, stack.nextText(font, &.{0xff}, 1));
    try t.expectError(error.MissingGlyph, stack.nextText(font, "B", 1));
    try t.expectError(error.InvalidScale, stack.nextText(font, "A", 0));
    try t.expectEqual(@as(f32, 0), (try stack.nextText(font, "A", 1)).y);
    try stack.pop();
}

test "horizontal region positions items with x spacing and preserves vertical nesting" {
    const t = std.testing;
    var stack: Stack = .{};
    try stack.push(.{ .x = 0, .y = 0, .width = 200, .height = 100 }, .{ .x = 2, .y = 4 });
    try stack.pushHorizontal(.{ .x = 10, .y = 20, .width = 120, .height = 30 }, .{ .x = 3, .y = 2 });
    const first = try stack.next(20, 8);
    try t.expectEqual(@as(f32, 10), first.x);
    try t.expectEqual(@as(f32, 22), first.y);
    const second = try stack.next(15, 12);
    try t.expectEqual(@as(f32, 33), second.x);
    try t.expectEqual(@as(f32, 22), second.y);
    try t.expectError(error.InvalidSize, stack.next(null, 4));
    try t.expectEqual(@as(f32, 51), (try stack.next(5, 4)).x);
    try stack.pop();
    try t.expectEqual(@as(f32, 0), (try stack.next(null, 10)).y);
    try stack.pop();
    try stack.validateBalanced();
}

test "horizontal invalid dimensions and coordinate overflow do not advance" {
    const t = std.testing;
    var stack: Stack = .{};
    try stack.pushHorizontal(.{ .x = 0, .y = 0, .width = 3.0e38, .height = 10 }, .{});
    _ = try stack.next(3.0e38, 5);
    try t.expectError(error.CoordinateOverflow, stack.next(3.0e38, 5));
    try t.expectError(error.InvalidSize, stack.next(-1, 5));
    try t.expectEqual(@as(usize, 1), stack.regions[0].items);
    try stack.pop();
}

test "cross-axis alignment in vertical and horizontal regions" {
    const t = std.testing;
    var stack: Stack = .{};
    try stack.push(.{ .x = 10, .y = 20, .width = 100, .height = 80 }, .{ .x = 5, .y = 3 });
    const a = try stack.nextAligned(20, 10, .center);
    try t.expectEqual(@as(f32, 50), a.x);
    try t.expectEqual(@as(f32, 20), a.y);
    const b = try stack.nextAligned(20, 10, .end);
    try t.expectEqual(@as(f32, 85), b.x);
    try t.expectEqual(@as(f32, 33), b.y);
    try stack.pop();

    try stack.pushHorizontal(.{ .x = 10, .y = 20, .width = 100, .height = 40 }, .{ .x = 2, .y = 5 });
    const c = try stack.nextAligned(10, 10, .center);
    try t.expectEqual(@as(f32, 10), c.x);
    try t.expectEqual(@as(f32, 35), c.y);
    const d = try stack.nextAligned(10, 10, .end);
    try t.expectEqual(@as(f32, 22), d.x);
    try t.expectEqual(@as(f32, 45), d.y);
    try stack.pop();
}

test "invalid cross-axis alignment preserves cursor" {
    const t = std.testing;
    var stack: Stack = .{};
    try stack.push(.{ .x = 0, .y = 0, .width = 20, .height = 30 }, .{ .x = 2 });
    try t.expectError(error.InvalidSize, stack.nextAligned(17, 5, .center));
    try t.expectEqual(@as(usize, 0), stack.regions[0].items);
    try t.expectEqual(@as(f32, 0), (try stack.nextAligned(10, 5, .start)).y);
    try stack.pop();
    try stack.pushHorizontal(.{ .x = 0, .y = 0, .width = 30, .height = 10 }, .{ .y = 2 });
    try t.expectError(error.InvalidSize, stack.nextAligned(5, 7, .end));
    try t.expectEqual(@as(f32, 0), (try stack.nextAligned(5, 6, .start)).x);
    try stack.pop();
}

test "fill remaining respects direction, spacing and region bounds" {
    const t = std.testing;
    var stack: Stack = .{};
    try stack.push(.{ .x = 10, .y = 20, .width = 100, .height = 50 }, .{ .x = 5, .y = 3 });
    _ = try stack.next(20, 10);
    const v = try stack.nextFillRemaining(90);
    try t.expectEqual(@as(f32, 33), v.y);
    try t.expectEqual(@as(f32, 37), v.height);
    try t.expectEqual(@as(f32, 15), v.x);
    try stack.pop();

    try stack.pushHorizontal(.{ .x = 10, .y = 20, .width = 100, .height = 50 }, .{ .x = 5, .y = 3 });
    _ = try stack.next(20, 10);
    const h = try stack.nextFillRemaining(44);
    try t.expectEqual(@as(f32, 35), h.x);
    try t.expectEqual(@as(f32, 75), h.width);
    try t.expectEqual(@as(f32, 23), h.y);
    try stack.pop();
}

test "fill remaining rejects invalid sizes and exhausted region atomically" {
    const t = std.testing;
    var stack: Stack = .{};
    try t.expectError(error.StackUnderflow, stack.nextFillRemaining(1));
    try stack.pushHorizontal(.{ .x = 0, .y = 0, .width = 20, .height = 10 }, .{ .x = 2, .y = 1 });
    try t.expectError(error.InvalidSize, stack.nextFillRemaining(9));
    try t.expectError(error.InvalidSize, stack.nextFillRemaining(-1));
    try t.expectEqual(@as(usize, 0), stack.regions[0].items);
    _ = try stack.next(21, 2);
    try t.expectError(error.InvalidSize, stack.nextFillRemaining(2));
    try t.expectEqual(@as(usize, 1), stack.regions[0].items);
    try stack.pop();
}

test "weighted horizontal allocation reserves future spacing" {
    const t = std.testing;
    var stack: Stack = .{};
    try stack.pushHorizontal(.{ .x = 10, .y = 20, .width = 100, .height = 30 }, .{ .x = 4, .y = 2 });
    const a = try stack.nextWeighted(1, 3, 1, 10);
    const b = try stack.nextWeighted(2, 2, 0, 10);
    try t.expectApproxEqAbs(@as(f32, 32), a.width, 0.0001);
    try t.expectApproxEqAbs(@as(f32, 64), b.width, 0.0001);
    try t.expectApproxEqAbs(@as(f32, 46), b.x, 0.0001);
    try t.expectApproxEqAbs(@as(f32, 110), b.x + b.width, 0.0001);
    try stack.pop();
}

test "weighted vertical layout and invalid operations remain atomic" {
    const t = std.testing;
    var stack: Stack = .{};
    try t.expectError(error.StackUnderflow, stack.nextWeighted(1, 1, 0, 10));
    try stack.push(.{ .x = 0, .y = 0, .width = 80, .height = 90 }, .{ .x = 2, .y = 5 });
    try t.expectError(error.InvalidSize, stack.nextWeighted(0, 1, 0, 10));
    try t.expectError(error.InvalidSize, stack.nextWeighted(2, 1, 0, 10));
    try t.expectError(error.InvalidSize, stack.nextWeighted(1, 1, 20, 10));
    try t.expectError(error.InvalidSize, stack.nextWeighted(1, 1, 0, 77));
    try t.expectEqual(@as(usize, 0), stack.regions[0].items);
    const a = try stack.nextWeighted(1, 2, 1, 30);
    const b = try stack.nextWeighted(1, 1, 0, 30);
    try t.expectApproxEqAbs(@as(f32, 42.5), a.height, 0.0001);
    try t.expectApproxEqAbs(@as(f32, 42.5), b.height, 0.0001);
    try t.expectApproxEqAbs(@as(f32, 47.5), b.y, 0.0001);
    try stack.pop();
}

// Stage 26.4: contract regression coverage for nested composition and invalid states.
test "nested horizontal and vertical regions preserve independent cursors" {
    const t = std.testing;
    var stack: Stack = .{};
    try stack.push(.{ .x = 0, .y = 0, .width = 300, .height = 200 }, .{ .x = 4, .y = 6 });
    const header = try stack.next(null, 20);
    try t.expectEqual(@as(f32, 0), header.y);
    try t.expectEqual(@as(f32, 292), header.width);

    try stack.pushHorizontal(.{ .x = 10, .y = 30, .width = 100, .height = 40 }, .{ .x = 5, .y = 3 });
    const first = try stack.nextWeighted(1, 3, 1, 20);
    const second = try stack.nextWeighted(2, 2, 0, 20);
    try t.expectApproxEqAbs(@as(f32, 31.666666), first.width, 0.0001);
    try t.expectApproxEqAbs(@as(f32, 63.333332), second.width, 0.0001);
    try t.expectApproxEqAbs(@as(f32, 110), second.x + second.width, 0.0001);
    try stack.pop();

    // A nested region must not consume the parent region's cursor.
    const after = try stack.next(40, 12);
    try t.expectEqual(@as(f32, 26), after.y);
    try t.expectEqual(@as(f32, 4), after.x);
    try stack.pop();
    try stack.validateBalanced();
}

test "weighted and fill failures preserve exact region state" {
    const t = std.testing;
    var stack: Stack = .{};
    try stack.pushHorizontal(.{ .x = 0, .y = 0, .width = 100, .height = 20 }, .{ .x = 3, .y = 2 });
    _ = try stack.next(10, 5);
    const before = stack.regions[0];
    try t.expectError(error.InvalidSize, stack.nextWeighted(1, 1, std.math.maxInt(usize), 5));
    try t.expectEqualDeep(before, stack.regions[0]);
    try t.expectError(error.InvalidSize, stack.nextWeighted(std.math.nan(f32), 1, 0, 5));
    try t.expectEqualDeep(before, stack.regions[0]);
    try t.expectError(error.InvalidSize, stack.nextFillRemaining(17));
    try t.expectEqualDeep(before, stack.regions[0]);
    const result = try stack.nextFillRemaining(16);
    try t.expectEqual(@as(f32, 13), result.x);
    try t.expectEqual(@as(f32, 87), result.width);
    try stack.pop();
}

test "corrupted depth cannot be popped into a valid-looking state" {
    const t = std.testing;
    var stack: Stack = .{};
    stack.depth = max_depth + 1;
    try t.expectError(error.StackUnderflow, stack.pop());
    try t.expectEqual(max_depth + 1, stack.depth);
    stack.reset();
    try stack.push(.{ .x = 0, .y = 0, .width = 10, .height = 10 }, .{});
    try stack.pop();
    try stack.validateBalanced();
}

test "layout maximum depth and atomic overflow boundary" {
    const t = std.testing;
    var stack: Stack = .{};
    for (0..max_depth) |_| {
        try stack.pushHorizontal(.{ .x = 0, .y = 0, .width = 100, .height = 20 }, .{});
    }
    try t.expectError(error.StackOverflow, stack.push(.{ .x = 0, .y = 0, .width = 1, .height = 1 }, .{}));
    try t.expectEqual(max_depth, stack.depth);
    _ = try stack.nextAligned(10, 5, .end);
    try t.expectEqual(@as(usize, 1), stack.regions[max_depth - 1].items);
    for (0..max_depth) |_| try stack.pop();
    try stack.validateBalanced();
}
