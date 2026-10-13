//! Caller-owned, fixed-capacity byte buffers. No heap allocations.
const std = @import("std");

pub const Error = error{ OutOfCapacity, SizeOverflow, InvalidAlignment, AddressOverflow };

/// The caller owns `storage` and must keep it alive while the arena is in use.
/// Returned slices remain valid until reset or until the caller modifies storage.
/// This arena returns byte slices only; typed/aligned storage is not implied.
pub const ByteArena = struct {
    storage: []u8,
    used: usize = 0,
    high_watermark: usize = 0,

    pub fn init(storage: []u8) ByteArena {
        return .{ .storage = storage };
    }

    pub fn reserve(self: *ByteArena, count: usize) Error![]u8 {
        const result = @addWithOverflow(self.used, count);
        if (result[1] != 0) return error.SizeOverflow;
        const end = result[0];
        if (end > self.storage.len) return error.OutOfCapacity;
        const slice = self.storage[self.used..end];
        self.used = end;
        self.high_watermark = @max(self.high_watermark, end);
        return slice;
    }

    /// Reserve bytes whose starting address is aligned to `alignment`.
    /// `alignment` must be a nonzero power of two. Padding counts against
    /// capacity; on any failure, used and high_watermark are unchanged.
    /// A zero-length reservation still computes alignment, but consumes no
    /// storage beyond the required padding.
    pub fn reserveAligned(self: *ByteArena, count: usize, alignment: usize) Error![]u8 {
        if (alignment == 0 or (alignment & (alignment - 1)) != 0)
            return error.InvalidAlignment;
        const address = @addWithOverflow(@intFromPtr(self.storage.ptr), self.used);
        if (address[1] != 0) return error.AddressOverflow;
        const mask = alignment - 1;
        const offset = (alignment - (address[0] & mask)) & mask;
        const aligned_used = @addWithOverflow(self.used, offset);
        if (aligned_used[1] != 0) return error.SizeOverflow;
        const end = @addWithOverflow(aligned_used[0], count);
        if (end[1] != 0) return error.SizeOverflow;
        if (end[0] > self.storage.len) return error.OutOfCapacity;
        const result = self.storage[aligned_used[0]..end[0]];
        self.used = end[0];
        self.high_watermark = @max(self.high_watermark, end[0]);
        return result;
    }

    pub fn reset(self: *ByteArena) void {
        self.used = 0;
    }

    pub fn remaining(self: *const ByteArena) usize {
        return self.storage.len - self.used;
    }
};

test "capacity, reset, and watermark" {
    const testing = std.testing;
    var bytes: [8]u8 = undefined;
    var arena = ByteArena.init(&bytes);
    const a = try arena.reserve(5);
    try testing.expectEqual(@as(usize, 5), a.len);
    try testing.expectError(error.OutOfCapacity, arena.reserve(4));
    try testing.expectEqual(@as(usize, 5), arena.used);
    arena.reset();
    try testing.expectEqual(@as(usize, 8), arena.remaining());
    try testing.expectEqual(@as(usize, 5), arena.high_watermark);
}

test "overflow does not mutate arena" {
    const testing = std.testing;
    var bytes: [4]u8 = undefined;
    var arena = ByteArena.init(&bytes);
    _ = try arena.reserve(1);
    try testing.expectError(error.SizeOverflow, arena.reserve(std.math.maxInt(usize)));
    try testing.expectEqual(@as(usize, 1), arena.used);
}

test "aligned reservations and padding" {
    const testing = std.testing;
    var storage: [96]u8 = undefined;
    var arena = ByteArena.init(storage[1..]);
    const a = try arena.reserveAligned(8, 16);
    try testing.expectEqual(@as(usize, 0), @intFromPtr(a.ptr) & 15);
    try testing.expectEqual(@as(usize, 8), a.len);
    const previous = arena.used;
    try testing.expectError(error.InvalidAlignment, arena.reserveAligned(1, 3));
    try testing.expectError(error.OutOfCapacity, arena.reserveAligned(200, 32));
    try testing.expectEqual(previous, arena.used);
    try testing.expectEqual(previous, arena.high_watermark);
    const b = try arena.reserveAligned(4, 8);
    try testing.expectEqual(@as(usize, 0), @intFromPtr(b.ptr) & 7);
    arena.reset();
    try testing.expectEqual(@as(usize, 0), arena.used);
    try testing.expect(arena.high_watermark >= previous);
}

test "aligned reservation rejects overflow without mutation" {
    const testing = std.testing;
    var storage: [16]u8 = undefined;
    var arena = ByteArena.init(&storage);
    try testing.expectError(error.SizeOverflow, arena.reserveAligned(std.math.maxInt(usize), 8));
    try testing.expectEqual(@as(usize, 0), arena.used);
}
