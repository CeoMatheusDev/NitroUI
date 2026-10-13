//! Backend-independent indexed geometry; all buffers belong to the engine.
const std = @import("std");

pub const Vertex = extern struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    color: u32, // RGBA8 packed as 0xAABBGGRR (numeric value)
};
pub const ClipRect = struct { min_x: f32, min_y: f32, max_x: f32, max_y: f32 };
pub const Command = struct {
    first_index: u32,
    index_count: u32,
    texture: u64,
    clip: ClipRect,
};
pub const Error = error{ OutOfCapacity, InvalidGeometry, InvalidClip, IndexOverflow };

pub const Buffer = struct {
    vertices: []Vertex,
    indices: []u32,
    commands: []Command,
    vertex_count: usize = 0,
    index_count: usize = 0,
    command_count: usize = 0,

    pub fn init(vertices: []Vertex, indices: []u32, commands: []Command) Buffer {
        return .{ .vertices = vertices, .indices = indices, .commands = commands };
    }
    pub fn reset(self: *Buffer) void {
        self.vertex_count = 0;
        self.index_count = 0;
        self.command_count = 0;
    }
    pub fn vertexSlice(self: *const Buffer) []const Vertex {
        return self.vertices[0..self.vertex_count];
    }
    pub fn indexSlice(self: *const Buffer) []const u32 {
        return self.indices[0..self.index_count];
    }
    pub fn commandSlice(self: *const Buffer) []const Command {
        return self.commands[0..self.command_count];
    }

    /// Append one filled triangle. Positions are logical display coordinates.
    /// The entire operation is rejected before writing if capacity is insufficient.
    pub fn addTriangle(self: *Buffer, a: [2]f32, b: [2]f32, c: [2]f32, color: u32, texture: u64, clip: ClipRect) Error!void {
        if (!valid(a[0]) or !valid(a[1]) or !valid(b[0]) or !valid(b[1]) or !valid(c[0]) or !valid(c[1])) return error.InvalidGeometry;
        if (!validClip(clip)) return error.InvalidClip;
        if (self.vertices.len - self.vertex_count < 3 or self.indices.len - self.index_count < 3) return error.OutOfCapacity;
        if (self.vertex_count > std.math.maxInt(u32) - 3 or self.index_count > std.math.maxInt(u32) - 3) return error.IndexOverflow;
        const merge = self.canMerge(texture, clip, 3);
        if (!merge and self.command_count == self.commands.len) return error.OutOfCapacity;
        const base: u32 = @intCast(self.vertex_count);
        const first: u32 = @intCast(self.index_count);
        @memcpy(self.vertices[self.vertex_count..][0..3], &[_]Vertex{
            .{ .x = a[0], .y = a[1], .u = 0, .v = 0, .color = color },
            .{ .x = b[0], .y = b[1], .u = 0, .v = 0, .color = color },
            .{ .x = c[0], .y = c[1], .u = 0, .v = 0, .color = color },
        });
        @memcpy(self.indices[self.index_count..][0..3], &[_]u32{ base, base + 1, base + 2 });
        self.vertex_count += 3;
        self.index_count += 3;
        if (merge) {
            self.commands[self.command_count - 1].index_count += 3;
        } else {
            self.commands[self.command_count] = .{ .first_index = first, .index_count = 3, .texture = texture, .clip = clip };
            self.command_count += 1;
        }
    }

    /// A thick line is represented by one quad. Zero-length lines are rejected.
    pub fn addLine(self: *Buffer, a: [2]f32, b: [2]f32, thickness: f32, color: u32, texture: u64, clip: ClipRect) Error!void {
        if (!valid(a[0]) or !valid(a[1]) or !valid(b[0]) or !valid(b[1]) or !valid(thickness) or thickness <= 0) return error.InvalidGeometry;
        const dx = b[0] - a[0];
        const dy = b[1] - a[1];
        const length = @sqrt(dx * dx + dy * dy);
        if (!valid(length) or length <= 0) return error.InvalidGeometry;
        const nx = -dy / length * (thickness * 0.5);
        const ny = dx / length * (thickness * 0.5);
        const points = [4][2]f32{
            .{ a[0] + nx, a[1] + ny }, .{ b[0] + nx, b[1] + ny },
            .{ b[0] - nx, b[1] - ny }, .{ a[0] - nx, a[1] - ny },
        };
        for (points) |point| {
            if (!valid(point[0]) or !valid(point[1])) return error.InvalidGeometry;
        }
        try self.addQuad(points, color, texture, clip);
    }

    /// Filled circle using a triangle fan; segment count is explicit and bounded.
    /// All capacity and arithmetic checks precede the first write.
    pub fn addCircle(self: *Buffer, center: [2]f32, radius: f32, segments: u16, color: u32, texture: u64, clip: ClipRect) Error!void {
        if (!valid(center[0]) or !valid(center[1]) or !valid(radius) or radius <= 0 or segments < 3 or segments > 256) return error.InvalidGeometry;
        if (!validClip(clip)) return error.InvalidClip;
        const n: usize = @intCast(segments);
        const vcount = n + 1;
        const icount = n * 3;
        if (self.vertices.len - self.vertex_count < vcount or self.indices.len - self.index_count < icount) return error.OutOfCapacity;
        if (self.vertex_count > std.math.maxInt(u32) - vcount or self.index_count > std.math.maxInt(u32) - icount) return error.IndexOverflow;
        const merge = self.canMerge(texture, clip, @intCast(icount));
        if (!merge and self.command_count == self.commands.len) return error.OutOfCapacity;
        // Prevalidate all generated coordinates so errors never leave partial geometry.
        const tau: f32 = 2.0 * std.math.pi;
        for (0..n) |i| {
            const angle = tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
            const x = center[0] + radius * @cos(angle);
            const y = center[1] + radius * @sin(angle);
            if (!valid(x) or !valid(y)) return error.InvalidGeometry;
        }
        const base: u32 = @intCast(self.vertex_count);
        const first: u32 = @intCast(self.index_count);
        self.vertices[self.vertex_count] = .{ .x = center[0], .y = center[1], .u = 0.5, .v = 0.5, .color = color };
        for (0..n) |i| {
            const angle = tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
            self.vertices[self.vertex_count + 1 + i] = .{
                .x = center[0] + radius * @cos(angle),
                .y = center[1] + radius * @sin(angle),
                .u = 0,
                .v = 0,
                .color = color,
            };
            const offset = self.index_count + i * 3;
            self.indices[offset] = base;
            self.indices[offset + 1] = base + 1 + @as(u32, @intCast(i));
            self.indices[offset + 2] = base + 1 + @as(u32, @intCast((i + 1) % n));
        }
        self.vertex_count += vcount;
        self.index_count += icount;
        if (merge) {
            self.commands[self.command_count - 1].index_count += @intCast(icount);
        } else {
            self.commands[self.command_count] = .{ .first_index = first, .index_count = @intCast(icount), .texture = texture, .clip = clip };
            self.command_count += 1;
        }
    }

    fn addQuad(self: *Buffer, points: [4][2]f32, color: u32, texture: u64, clip: ClipRect) Error!void {
        if (!validClip(clip)) return error.InvalidClip;
        if (self.vertices.len - self.vertex_count < 4 or self.indices.len - self.index_count < 6) return error.OutOfCapacity;
        if (self.vertex_count > std.math.maxInt(u32) - 4 or self.index_count > std.math.maxInt(u32) - 6) return error.IndexOverflow;
        const merge = self.canMerge(texture, clip, 6);
        if (!merge and self.command_count == self.commands.len) return error.OutOfCapacity;
        const base: u32 = @intCast(self.vertex_count);
        const first: u32 = @intCast(self.index_count);
        for (points, 0..) |point, i| {
            self.vertices[self.vertex_count + i] = .{ .x = point[0], .y = point[1], .u = 0, .v = 0, .color = color };
        }
        @memcpy(self.indices[self.index_count..][0..6], &[_]u32{ base, base + 1, base + 2, base, base + 2, base + 3 });
        self.vertex_count += 4;
        self.index_count += 6;
        if (merge) {
            self.commands[self.command_count - 1].index_count += 6;
        } else {
            self.commands[self.command_count] = .{ .first_index = first, .index_count = 6, .texture = texture, .clip = clip };
            self.command_count += 1;
        }
    }

    fn canMerge(self: *const Buffer, texture: u64, clip: ClipRect, extra_indices: u32) bool {
        if (self.command_count == 0) return false;
        const prev = self.commands[self.command_count - 1];
        return prev.texture == texture and std.meta.eql(prev.clip, clip) and
            prev.index_count <= std.math.maxInt(u32) - extra_indices and
            @as(u64, prev.first_index) + @as(u64, prev.index_count) == @as(u64, @intCast(self.index_count));
    }

    /// Append a rectangle as two triangles. Validation is atomic: no partial writes.
    /// Coordinates and clip use logical display pixels; origin is top-left.
    pub fn addRect(self: *Buffer, x0: f32, y0: f32, x1: f32, y1: f32, color: u32, texture: u64, clip: ClipRect) Error!void {
        if (!valid(x0) or !valid(y0) or !valid(x1) or !valid(y1) or x1 < x0 or y1 < y0) return error.InvalidGeometry;
        if (!validClip(clip)) return error.InvalidClip;
        if (self.vertices.len - self.vertex_count < 4 or self.indices.len - self.index_count < 6) return error.OutOfCapacity;
        if (self.vertex_count > std.math.maxInt(u32) - 4 or self.index_count > std.math.maxInt(u32) - 6) return error.IndexOverflow;
        const merge = self.canMerge(texture, clip, 6);
        if (!merge and self.command_count == self.commands.len) return error.OutOfCapacity;
        const base: u32 = @intCast(self.vertex_count);
        const first: u32 = @intCast(self.index_count);
        @memcpy(self.vertices[self.vertex_count..][0..4], &[_]Vertex{
            .{ .x = x0, .y = y0, .u = 0, .v = 0, .color = color },
            .{ .x = x1, .y = y0, .u = 1, .v = 0, .color = color },
            .{ .x = x1, .y = y1, .u = 1, .v = 1, .color = color },
            .{ .x = x0, .y = y1, .u = 0, .v = 1, .color = color },
        });
        @memcpy(self.indices[self.index_count..][0..6], &[_]u32{ base, base + 1, base + 2, base, base + 2, base + 3 });
        self.vertex_count += 4;
        self.index_count += 6;
        if (merge) {
            self.commands[self.command_count - 1].index_count += 6;
        } else {
            self.commands[self.command_count] = .{ .first_index = first, .index_count = 6, .texture = texture, .clip = clip };
            self.command_count += 1;
        }
    }
};
fn valid(value: f32) bool {
    return std.math.isFinite(value);
}
fn validClip(clip: ClipRect) bool {
    return valid(clip.min_x) and valid(clip.min_y) and valid(clip.max_x) and valid(clip.max_y) and
        clip.max_x >= clip.min_x and clip.max_y >= clip.min_y;
}

test "adjacent compatible rectangles batch and reset" {
    var vertices: [8]Vertex = undefined;
    var indices: [12]u32 = undefined;
    var commands: [2]Command = undefined;
    var buffer = Buffer.init(&vertices, &indices, &commands);
    const clip: ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try buffer.addRect(0, 0, 10, 10, 0xffffffff, 1, clip);
    try buffer.addRect(10, 0, 20, 10, 0xffffffff, 1, clip);
    try std.testing.expectEqual(@as(usize, 1), buffer.command_count);
    try std.testing.expectEqual(@as(u32, 12), buffer.commands[0].index_count);
    try std.testing.expectEqual(@as(u32, 4), buffer.indices[6]);
    try std.testing.expectError(error.OutOfCapacity, buffer.addRect(0, 0, 1, 1, 0, 1, clip));
    try std.testing.expectEqual(@as(usize, 8), buffer.vertex_count);
    buffer.reset();
    try std.testing.expectEqual(@as(usize, 0), buffer.command_count);
}

test "invalid clip and command capacity do not modify counts" {
    var vertices: [8]Vertex = undefined;
    var indices: [12]u32 = undefined;
    var commands: [1]Command = undefined;
    var buffer = Buffer.init(&vertices, &indices, &commands);
    const clip: ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 10, .max_y = 10 };
    try std.testing.expectError(error.InvalidClip, buffer.addRect(0, 0, 1, 1, 0, 1, .{ .min_x = 2, .min_y = 0, .max_x = 1, .max_y = 10 }));
    try buffer.addRect(0, 0, 1, 1, 0, 1, clip);
    try std.testing.expectError(error.OutOfCapacity, buffer.addRect(0, 0, 1, 1, 0, 2, clip));
    try std.testing.expectEqual(@as(usize, 4), buffer.vertex_count);
}

test "triangles batch with rectangles and preserve index order" {
    var vertices: [10]Vertex = undefined;
    var indices: [15]u32 = undefined;
    var commands: [2]Command = undefined;
    var buffer = Buffer.init(&vertices, &indices, &commands);
    const clip: ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try buffer.addTriangle(.{ 0, 0 }, .{ 10, 0 }, .{ 0, 10 }, 0xffffffff, 2, clip);
    try buffer.addRect(10, 10, 20, 20, 0xffffffff, 2, clip);
    try std.testing.expectEqual(@as(usize, 1), buffer.command_count);
    try std.testing.expectEqual(@as(u32, 9), buffer.commands[0].index_count);
    try std.testing.expectEqual(@as(u32, 3), buffer.indices[3]);
    try buffer.addTriangle(.{ 1, 1 }, .{ 2, 1 }, .{ 1, 2 }, 0xffffffff, 3, clip);
    try std.testing.expectEqual(@as(usize, 2), buffer.command_count);
    try std.testing.expectEqual(@as(u32, 9), buffer.commands[1].first_index);
}

test "triangle invalid inputs and capacity failures are atomic" {
    var vertices: [3]Vertex = undefined;
    var indices: [3]u32 = undefined;
    var commands: [1]Command = undefined;
    var buffer = Buffer.init(&vertices, &indices, &commands);
    const clip: ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 10, .max_y = 10 };
    try std.testing.expectError(error.InvalidGeometry, buffer.addTriangle(.{ std.math.inf(f32), 0 }, .{ 1, 0 }, .{ 0, 1 }, 0, 0, clip));
    try std.testing.expectEqual(@as(usize, 0), buffer.vertex_count);
    try buffer.addTriangle(.{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, 0, 0, clip);
    try std.testing.expectError(error.OutOfCapacity, buffer.addTriangle(.{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, 0, 0, clip));
    try std.testing.expectEqual(@as(usize, 3), buffer.vertex_count);
    try std.testing.expectEqual(@as(usize, 3), buffer.index_count);
}

test "line and circle batching, capacity, invalid geometry" {
    var vertices: [9]Vertex = undefined;
    var indices: [18]u32 = undefined;
    var commands: [1]Command = undefined;
    var buffer = Buffer.init(&vertices, &indices, &commands);
    const region: ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try buffer.addLine(.{ 0, 0 }, .{ 10, 0 }, 2, 0xffffffff, 0, region);
    try std.testing.expectEqual(@as(usize, 4), buffer.vertex_count);
    try std.testing.expectError(error.InvalidGeometry, buffer.addLine(.{ 0, 0 }, .{ 0, 0 }, 2, 0, 0, region));
    try buffer.addCircle(.{ 20, 20 }, 5, 4, 0xffffffff, 0, region);
    try std.testing.expectEqual(@as(usize, 9), buffer.vertex_count);
    try std.testing.expectEqual(@as(usize, 18), buffer.index_count);
    try std.testing.expectEqual(@as(usize, 1), buffer.command_count);
    try std.testing.expectError(error.OutOfCapacity, buffer.addCircle(.{ 20, 20 }, 5, 4, 0, 0, region));
    try std.testing.expectError(error.InvalidGeometry, buffer.addCircle(.{ 20, 20 }, 5, 2, 0, 0, region));
    try std.testing.expectEqual(@as(usize, 18), buffer.index_count);
}
