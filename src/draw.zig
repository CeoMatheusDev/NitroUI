//! Backend-independent indexed geometry; all buffers belong to the engine.
const std = @import("std");

pub const Vertex = extern struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    color: u32, // RGBA8 packed as 0xAABBGGRR (numeric value)
};
pub const CornerRadii = struct { top_left: f32, top_right: f32, bottom_right: f32, bottom_left: f32 };
pub const ClipRect = struct { min_x: f32, min_y: f32, max_x: f32, max_y: f32 };
pub const Command = struct {
    first_index: u32,
    index_count: u32,
    texture: u64,
    clip: ClipRect,
};
pub const Error = error{ OutOfCapacity, InvalidGeometry, InvalidClip, IndexOverflow };

/// Borrowed, read-only view of the geometry produced for one frame.
/// The backing storage belongs to the engine. The slices are valid only while
/// the owning Context remains in the ready state, before releaseFrame().
/// `const` restricts mutation through this view; it does not prevent the
/// storage owner from modifying or reusing the same memory.
pub const View = struct {
    vertices: []const Vertex,
    indices: []const u32,
    commands: []const Command,
};

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
    /// Return only initialized elements, without copying the buffers.
    /// Caller must ensure the public counters satisfy the buffer invariants.
    pub fn view(self: *const Buffer) View {
        return .{
            .vertices = self.vertexSlice(),
            .indices = self.indexSlice(),
            .commands = self.commandSlice(),
        };
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

    /// Validate caller-visible counters and capacity before any buffer access.
    /// Public counters remain writable for API compatibility in 0.1.0.
    fn preflight(self: *const Buffer, vertices_needed: usize, indices_needed: usize) Error!void {
        if (self.vertex_count > self.vertices.len or self.index_count > self.indices.len or self.command_count > self.commands.len) return error.OutOfCapacity;
        if (self.vertex_count > std.math.maxInt(u32) or self.index_count > std.math.maxInt(u32)) return error.IndexOverflow;
        if (vertices_needed > std.math.maxInt(u32) - self.vertex_count or indices_needed > std.math.maxInt(u32) - self.index_count) return error.IndexOverflow;
        if (self.vertices.len - self.vertex_count < vertices_needed or self.indices.len - self.index_count < indices_needed) return error.OutOfCapacity;
        if (self.command_count > 0) {
            const previous = self.commands[self.command_count - 1];
            const end = @as(u64, previous.first_index) + @as(u64, previous.index_count);
            if (end != @as(u64, @intCast(self.index_count))) return error.InvalidGeometry;
        } else if (self.index_count != 0) {
            return error.InvalidGeometry;
        }
    }

    /// Append one filled triangle. Positions are logical display coordinates.
    /// The entire operation is rejected before writing if capacity is insufficient.
    pub fn addTriangle(self: *Buffer, a: [2]f32, b: [2]f32, c: [2]f32, color: u32, texture: u64, clip: ClipRect) Error!void {
        if (!valid(a[0]) or !valid(a[1]) or !valid(b[0]) or !valid(b[1]) or !valid(c[0]) or !valid(c[1])) return error.InvalidGeometry;
        if (!validClip(clip)) return error.InvalidClip;
        try self.preflight(3, 3);
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
        try self.preflight(vcount, icount);
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

    /// Filled rounded rectangle with independent corner radii.
    /// segments_per_corner is 1..32. Geometry and capacity are validated before writing.
    /// UVs are (0,0), matching untextured triangle geometry; texture is a batching handle.
    pub fn addRoundedRect(self: *Buffer, x0: f32, y0: f32, x1: f32, y1: f32, radii: CornerRadii, segments_per_corner: u8, color: u32, texture: u64, clip_rect: ClipRect) Error!void {
        if (!valid(x0) or !valid(y0) or !valid(x1) or !valid(y1) or x1 <= x0 or y1 <= y0) return error.InvalidGeometry;
        if (!validClip(clip_rect)) return error.InvalidClip;
        if (segments_per_corner == 0 or segments_per_corner > 32) return error.InvalidGeometry;
        var r = [4]f32{ radii.top_left, radii.top_right, radii.bottom_right, radii.bottom_left };
        for (r) |radius| {
            if (!valid(radius) or radius < 0) return error.InvalidGeometry;
        }
        if (r[0] == 0 and r[1] == 0 and r[2] == 0 and r[3] == 0) return self.addRect(x0, y0, x1, y1, color, texture, clip_rect);
        const width = x1 - x0;
        const height = y1 - y0;
        if (!valid(width) or !valid(height)) return error.InvalidGeometry;
        // CSS-style uniform scaling prevents adjacent radii from overlapping.
        var scale: f32 = 1;
        const pairs = [4]struct { sum: f32, limit: f32 }{
            .{ .sum = r[0] + r[1], .limit = width },
            .{ .sum = r[1] + r[2], .limit = height },
            .{ .sum = r[2] + r[3], .limit = width },
            .{ .sum = r[3] + r[0], .limit = height },
        };
        for (pairs) |pair| {
            if (pair.sum > pair.limit) scale = @min(scale, pair.limit / pair.sum);
        }
        for (&r) |*radius| radius.* *= scale;
        const n: usize = @intCast(segments_per_corner);
        const perimeter = 4 * (n + 1);
        const vcount = perimeter + 1;
        const icount = perimeter * 3;
        if (self.vertex_count > self.vertices.len or self.index_count > self.indices.len or self.command_count > self.commands.len) return error.OutOfCapacity;
        try self.preflight(vcount, icount);
        const merge = self.canMerge(texture, clip_rect, @intCast(icount));
        if (!merge and self.command_count == self.commands.len) return error.OutOfCapacity;
        const centers = [4][2]f32{
            .{ x0 + r[0], y0 + r[0] }, .{ x1 - r[1], y0 + r[1] },
            .{ x1 - r[2], y1 - r[2] }, .{ x0 + r[3], y1 - r[3] },
        };
        const start_angles = [4]f32{ std.math.pi, 1.5 * std.math.pi, 0, 0.5 * std.math.pi };
        const step: f32 = (0.5 * std.math.pi) / @as(f32, @floatFromInt(n));
        const mid_x = x0 + width * 0.5;
        const mid_y = y0 + height * 0.5;
        if (!valid(mid_x) or !valid(mid_y)) return error.InvalidGeometry;
        // Preflight ensures an error cannot leave partially appended geometry.
        for (0..4) |corner| {
            for (0..n + 1) |i| {
                const angle = start_angles[corner] + step * @as(f32, @floatFromInt(i));
                const px = centers[corner][0] + r[corner] * @cos(angle);
                const py = centers[corner][1] + r[corner] * @sin(angle);
                if (!valid(px) or !valid(py)) return error.InvalidGeometry;
            }
        }
        const base: u32 = @intCast(self.vertex_count);
        const first: u32 = @intCast(self.index_count);
        self.vertices[self.vertex_count] = .{ .x = mid_x, .y = mid_y, .u = 0, .v = 0, .color = color };
        for (0..4) |corner| {
            for (0..n + 1) |i| {
                const angle = start_angles[corner] + step * @as(f32, @floatFromInt(i));
                self.vertices[self.vertex_count + 1 + corner * (n + 1) + i] = .{
                    .x = centers[corner][0] + r[corner] * @cos(angle),
                    .y = centers[corner][1] + r[corner] * @sin(angle),
                    .u = 0,
                    .v = 0,
                    .color = color,
                };
            }
        }
        for (0..perimeter) |i| {
            const offset = self.index_count + i * 3;
            self.indices[offset] = base;
            self.indices[offset + 1] = base + 1 + @as(u32, @intCast(i));
            self.indices[offset + 2] = base + 1 + @as(u32, @intCast((i + 1) % perimeter));
        }
        self.vertex_count += vcount;
        self.index_count += icount;
        if (merge) {
            self.commands[self.command_count - 1].index_count += @intCast(icount);
        } else {
            self.commands[self.command_count] = .{ .first_index = first, .index_count = @intCast(icount), .texture = texture, .clip = clip_rect };
            self.command_count += 1;
        }
    }

    /// Append one textured quad. Positions and UVs are supplied explicitly.
    /// The operation is atomic: validation/capacity failures perform no writes.
    pub fn addTexturedQuad(self: *Buffer, positions: [4][2]f32, uvs: [4][2]f32, color: u32, texture: u64, clip: ClipRect) Error!void {
        if (!validClip(clip)) return error.InvalidClip;
        for (positions) |point| {
            if (!valid(point[0]) or !valid(point[1])) return error.InvalidGeometry;
        }
        for (uvs) |uv_coord| {
            if (!valid(uv_coord[0]) or !valid(uv_coord[1])) return error.InvalidGeometry;
        }
        try self.preflight(4, 6);
        const merge = self.canMerge(texture, clip, 6);
        if (!merge and self.command_count == self.commands.len) return error.OutOfCapacity;
        const base: u32 = @intCast(self.vertex_count);
        const first: u32 = @intCast(self.index_count);
        for (positions, uvs, 0..) |point, uv_coord, i| {
            self.vertices[self.vertex_count + i] = .{ .x = point[0], .y = point[1], .u = uv_coord[0], .v = uv_coord[1], .color = color };
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

    fn addQuad(self: *Buffer, points: [4][2]f32, color: u32, texture: u64, clip: ClipRect) Error!void {
        if (!validClip(clip)) return error.InvalidClip;
        try self.preflight(4, 6);
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
        try self.preflight(4, 6);
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

test "draw audit: failed append preserves geometry and command metadata" {
    var vertices: [8]Vertex = undefined;
    var indices: [12]u32 = undefined;
    var commands: [1]Command = undefined;
    var buffer = Buffer.init(&vertices, &indices, &commands);
    const region: ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try buffer.addRect(0, 0, 10, 10, 0xffffffff, 1, region);
    const before = buffer.commands[0];
    try std.testing.expectError(error.OutOfCapacity, buffer.addTriangle(.{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, 0, 2, region));
    try std.testing.expectEqual(@as(usize, 4), buffer.vertex_count);
    try std.testing.expectEqual(@as(usize, 6), buffer.index_count);
    try std.testing.expectEqual(@as(usize, 1), buffer.command_count);
    try std.testing.expect(std.meta.eql(before, buffer.commands[0]));
    try buffer.addRect(10, 0, 20, 10, 0xffffffff, 1, region);
    try std.testing.expectEqual(@as(u32, 12), buffer.commands[0].index_count);
}

test "draw audit: indices remain in bounds across mixed primitives" {
    var vertices: [32]Vertex = undefined;
    var indices: [64]u32 = undefined;
    var commands: [4]Command = undefined;
    var buffer = Buffer.init(&vertices, &indices, &commands);
    const region: ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try buffer.addRect(0, 0, 10, 10, 0xffffffff, 0, region);
    try buffer.addTriangle(.{ 0, 0 }, .{ 10, 0 }, .{ 0, 10 }, 0xffffffff, 0, region);
    try buffer.addLine(.{ 0, 20 }, .{ 20, 20 }, 2, 0xffffffff, 0, region);
    try buffer.addCircle(.{ 30, 30 }, 5, 8, 0xffffffff, 0, region);
    try std.testing.expectEqual(@as(usize, 1), buffer.command_count);
    try std.testing.expectEqual(@as(u32, @intCast(buffer.index_count)), buffer.commands[0].index_count);
    for (buffer.indexSlice()) |idx| {
        try std.testing.expect(@as(usize, idx) < buffer.vertex_count);
    }
}

test "draw audit: clip and texture changes split commands" {
    var vertices: [16]Vertex = undefined;
    var indices: [24]u32 = undefined;
    var commands: [4]Command = undefined;
    var buffer = Buffer.init(&vertices, &indices, &commands);
    const a: ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    const b: ClipRect = .{ .min_x = 1, .min_y = 0, .max_x = 100, .max_y = 100 };
    try buffer.addRect(0, 0, 10, 10, 0, 1, a);
    try buffer.addRect(0, 0, 10, 10, 0, 1, b);
    try buffer.addRect(0, 0, 10, 10, 0, 2, b);
    try buffer.addRect(0, 0, 10, 10, 0, 2, b);
    try std.testing.expectEqual(@as(usize, 3), buffer.command_count);
    try std.testing.expectEqual(@as(u32, 0), buffer.commands[0].first_index);
    try std.testing.expectEqual(@as(u32, 6), buffer.commands[1].first_index);
    try std.testing.expectEqual(@as(u32, 12), buffer.commands[2].first_index);
    try std.testing.expectEqual(@as(u32, 12), buffer.commands[2].index_count);
}

test "rounded rectangle indices and batching" {
    var vertices: [64]Vertex = undefined;
    var indices: [180]u32 = undefined;
    var commands: [2]Command = undefined;
    var buffer = Buffer.init(&vertices, &indices, &commands);
    const region: ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 200, .max_y = 200 };
    const radii: CornerRadii = .{ .top_left = 6, .top_right = 10, .bottom_right = 8, .bottom_left = 2 };
    try buffer.addRoundedRect(0, 0, 40, 30, radii, 3, 0xffffffff, 0, region);
    try std.testing.expectEqual(@as(usize, 17), buffer.vertex_count);
    try std.testing.expectEqual(@as(usize, 48), buffer.index_count);
    for (buffer.indexSlice()) |index| try std.testing.expect(index < buffer.vertex_count);
    try buffer.addRoundedRect(40, 0, 80, 30, radii, 3, 0xffffffff, 0, region);
    try std.testing.expectEqual(@as(usize, 1), buffer.command_count);
    try std.testing.expectEqual(@as(u32, 96), buffer.commands[0].index_count);
}

test "rounded rectangle invalid geometry and capacity are atomic" {
    var vertices: [17]Vertex = undefined;
    var indices: [48]u32 = undefined;
    var commands: [1]Command = undefined;
    var buffer = Buffer.init(&vertices, &indices, &commands);
    const region: ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    const radii: CornerRadii = .{ .top_left = 100, .top_right = 100, .bottom_right = 100, .bottom_left = 100 };
    try std.testing.expectError(error.InvalidGeometry, buffer.addRoundedRect(0, 0, 20, 10, radii, 0, 0, 0, region));
    try std.testing.expectEqual(@as(usize, 0), buffer.vertex_count);
    try buffer.addRoundedRect(0, 0, 20, 10, radii, 3, 0, 0, region);
    try std.testing.expectEqual(@as(usize, 17), buffer.vertex_count);
    try std.testing.expectError(error.OutOfCapacity, buffer.addRoundedRect(20, 0, 40, 10, radii, 3, 0, 0, region));
    try std.testing.expectEqual(@as(usize, 17), buffer.vertex_count);
    try std.testing.expectEqual(@as(usize, 48), buffer.index_count);
    try std.testing.expectEqual(@as(usize, 1), buffer.command_count);
}

test "zero radii use rectangle geometry" {
    var vertices: [4]Vertex = undefined;
    var indices: [6]u32 = undefined;
    var commands: [1]Command = undefined;
    var buffer = Buffer.init(&vertices, &indices, &commands);
    const region: ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try buffer.addRoundedRect(0, 0, 20, 10, .{ .top_left = 0, .top_right = 0, .bottom_right = 0, .bottom_left = 0 }, 4, 0, 0, region);
    try std.testing.expectEqual(@as(usize, 4), buffer.vertex_count);
    try std.testing.expectEqual(@as(usize, 6), buffer.index_count);
}

test "draw preflight rejects invalid public counters without writes" {
    var vertices: [4]Vertex = undefined;
    var indices: [6]u32 = undefined;
    var commands: [1]Command = undefined;
    const region: ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    var buffer = Buffer.init(&vertices, &indices, &commands);
    buffer.vertex_count = 5;
    try std.testing.expectError(error.OutOfCapacity, buffer.addRect(0, 0, 1, 1, 0, 0, region));
    try std.testing.expectEqual(@as(usize, 5), buffer.vertex_count);
    buffer.vertex_count = 0;
    buffer.index_count = 7;
    try std.testing.expectError(error.OutOfCapacity, buffer.addTriangle(.{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, 0, 0, region));
    buffer.index_count = 0;
    buffer.command_count = 2;
    try std.testing.expectError(error.OutOfCapacity, buffer.addCircle(.{ 5, 5 }, 2, 8, 0, 0, region));
    buffer.command_count = 0;
    try buffer.addRect(0, 0, 1, 1, 0, 0, region);
    try std.testing.expectEqual(@as(usize, 1), buffer.command_count);
}

test "draw preflight rejects inconsistent last command without writes" {
    var vertices: [8]Vertex = undefined;
    var indices: [12]u32 = undefined;
    var commands: [2]Command = undefined;
    const region: ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    var buffer = Buffer.init(&vertices, &indices, &commands);
    try buffer.addRect(0, 0, 1, 1, 0, 0, region);
    buffer.commands[0].index_count = 7;
    try std.testing.expectError(error.InvalidGeometry, buffer.addRect(1, 0, 2, 1, 0, 0, region));
    try std.testing.expectEqual(@as(usize, 4), buffer.vertex_count);
    try std.testing.expectEqual(@as(usize, 6), buffer.index_count);
    try std.testing.expectEqual(@as(usize, 1), buffer.command_count);
}
