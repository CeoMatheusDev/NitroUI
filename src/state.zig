//! Fixed-capacity persistent widget state, caller-owned storage.
//! Linear probing; table collisions are resolved by comparing complete IDs.
const std = @import("std");

pub const Error = error{ OutOfCapacity, InvalidCapacity };
pub const Value = u64;
pub const Entry = struct {
    id: u64 = 0,
    value: Value = 0,
    last_seen: u64 = 0,
    occupied: bool = false,
};

pub const Table = struct {
    entries: []Entry,
    count: usize = 0,

    /// Storage must be initialized before first use and remain valid.
    /// Replacing storage discards all previously stored values.
    pub fn init(storage: []Entry) Error!Table {
        if (storage.len == 0) return error.InvalidCapacity;
        @memset(storage, .{});
        return .{ .entries = storage };
    }

    fn start(self: *const Table, id: u64) usize {
        // Multiplicative mixing; this is not the widget ID hash.
        return @as(usize, @truncate(id *% 0x9e3779b97f4a7c15)) % self.entries.len;
    }

    pub fn get(self: *Table, id: u64) ?*Entry {
        var index = self.start(id);
        var visited: usize = 0;
        while (visited < self.entries.len) : (visited += 1) {
            const entry = &self.entries[index];
            if (!entry.occupied) return null;
            if (entry.id == id) return entry;
            index = if (index + 1 == self.entries.len) 0 else index + 1;
        }
        return null;
    }

    /// Existing IDs retain their values. New entries start at zero.
    /// Failure leaves the table unchanged.
    pub fn getOrPut(self: *Table, id: u64, frame: u64) Error!*Entry {
        var index = self.start(id);
        var visited: usize = 0;
        while (visited < self.entries.len) : (visited += 1) {
            const entry = &self.entries[index];
            if (!entry.occupied) {
                entry.* = .{ .id = id, .occupied = true, .last_seen = frame };
                self.count += 1;
                return entry;
            }
            if (entry.id == id) {
                entry.last_seen = frame;
                return entry;
            }
            index = if (index + 1 == self.entries.len) 0 else index + 1;
        }
        return error.OutOfCapacity;
    }

    /// Remove stale entries using backward-shift deletion. Does not allocate.
    /// Worst-case O(capacity^2) across the entire prune operation.
    pub fn prune(self: *Table, min_frame: u64) void {
        var index: usize = 0;
        while (index < self.entries.len) {
            if (!self.entries[index].occupied or self.entries[index].last_seen >= min_frame) {
                index += 1;
                continue;
            }

            self.removeAt(index);
            // A survivor may have shifted into index, so inspect it again.
            index = 0;
        }
    }

    fn probeDistance(self: *const Table, home: usize, position: usize) usize {
        return if (position >= home)
            position - home
        else
            self.entries.len - home + position;
    }

    /// A deletion always leaves at least one empty slot, even in a full table.
    fn removeAt(self: *Table, position: usize) void {
        var hole = position;
        self.entries[hole] = .{};
        self.count -= 1;

        var scan = if (hole + 1 == self.entries.len) 0 else hole + 1;
        while (self.entries[scan].occupied) {
            const home = self.start(self.entries[scan].id);
            if (self.probeDistance(home, hole) < self.probeDistance(home, scan)) {
                self.entries[hole] = self.entries[scan];
                self.entries[scan] = .{};
                hole = scan;
            }
            scan = if (scan + 1 == self.entries.len) 0 else scan + 1;
        }
    }
};

test "persistent values and collisions" {
    var storage: [4]Entry = undefined;
    var table = try Table.init(&storage);
    (try table.getOrPut(0, 1)).value = 19;
    (try table.getOrPut(4, 1)).value = 23;
    try std.testing.expectEqual(@as(u64, 19), table.get(0).?.value);
    try std.testing.expectEqual(@as(u64, 23), (try table.getOrPut(4, 2)).value);
    try std.testing.expectEqual(@as(usize, 2), table.count);
}

test "capacity and pruning preserve probe chains" {
    var storage: [2]Entry = undefined;
    var table = try Table.init(&storage);
    (try table.getOrPut(1, 1)).value = 10;
    (try table.getOrPut(3, 3)).value = 30;
    try std.testing.expectError(error.OutOfCapacity, table.getOrPut(5, 3));
    table.prune(2);
    try std.testing.expect(table.get(1) == null);
    try std.testing.expectEqual(@as(u64, 30), table.get(3).?.value);
    _ = try table.getOrPut(5, 4);
}

// Regression: a full, wrap-around probe cluster must remain searchable after
// pruning its head and must accept a new entry without corrupting survivors.
test "prune full wraparound cluster preserves survivors" {
    const testing = std.testing;
    var storage: [4]Entry = undefined;
    var table = try Table.init(&storage);
    // For capacity 4, odd multiplication preserves the low two bits.
    (try table.getOrPut(3, 1)).value = 33;
    (try table.getOrPut(7, 3)).value = 77;
    (try table.getOrPut(11, 3)).value = 111;
    (try table.getOrPut(15, 3)).value = 155;
    try testing.expectEqual(@as(usize, 4), table.count);
    table.prune(2);
    try testing.expect(table.get(3) == null);
    try testing.expectEqual(@as(u64, 77), table.get(7).?.value);
    try testing.expectEqual(@as(u64, 111), table.get(11).?.value);
    try testing.expectEqual(@as(u64, 155), table.get(15).?.value);
    try testing.expectEqual(@as(usize, 3), table.count);
    (try table.getOrPut(19, 4)).value = 199;
    try testing.expectEqual(@as(u64, 199), table.get(19).?.value);
    try testing.expectEqual(@as(usize, 4), table.count);
}

// A deterministic reference model verifies pruning under collisions and wraparound.
test "prune matches reference model across dense tables" {
    const testing = std.testing;
    const capacities = [_]usize{ 1, 2, 3, 4, 7, 8, 16 };
    inline for (capacities) |capacity| {
        var storage: [capacity]Entry = undefined;
        var table = try Table.init(&storage);
        var expected: [capacity]u64 = undefined;
        for (0..capacity) |i| {
            // Deliberately force collisions for power-of-two capacities.
            const id: u64 = @intCast(3 + i * 16);
            expected[i] = id;
            (try table.getOrPut(id, @intCast(i % 4))).value = id ^ 0x55aa;
        }
        table.prune(2);
        var survivors: usize = 0;
        for (expected, 0..) |id, i| {
            const found = table.get(id);
            if (i % 4 >= 2) {
                survivors += 1;
                try testing.expect(found != null);
                try testing.expectEqual(id ^ 0x55aa, found.?.value);
            } else {
                try testing.expect(found == null);
            }
        }
        try testing.expectEqual(survivors, table.count);
        table.prune(2);
        try testing.expectEqual(survivors, table.count);
    }
}

// Seeded differential test: 500 mixed getOrPut/get/prune operations against
// a linear reference model, with a 24-ID space over capacity 16 to force
// collisions, evictions and full-table failures deterministically.
test "seeded operations match linear reference model" {
    const testing = std.testing;
    var prng = std.Random.DefaultPrng.init(0xC0FFEE);
    const rand = prng.random();
    const cap = 16;
    const id_space = 24;
    const steps = 500;
    var storage: [cap]Entry = undefined;
    var table = try Table.init(&storage);
    var ref_alive: [id_space]bool = @splat(false);
    var ref_value: [id_space]u64 = @splat(0);
    var ref_seen: [id_space]u64 = @splat(0);
    var ref_count: usize = 0;
    for (0..steps) |step| {
        const frame: u64 = @intCast(step);
        const idx: usize = rand.intRangeLessThan(usize, 0, id_space);
        const id: u64 = @intCast(idx);
        switch (rand.intRangeLessThan(u8, 0, 3)) {
            0 => {
                const res = table.getOrPut(id, frame);
                if (ref_alive[idx]) {
                    const e = try res;
                    try testing.expectEqual(id, e.id);
                    ref_seen[idx] = frame;
                    e.value = id * 100003 + frame;
                    ref_value[idx] = e.value;
                    try testing.expectEqual(frame, e.last_seen);
                } else if (ref_count < cap) {
                    const e = try res;
                    e.value = id * 100003 + frame;
                    ref_alive[idx] = true;
                    ref_value[idx] = e.value;
                    ref_seen[idx] = frame;
                    ref_count += 1;
                } else {
                    try testing.expectError(error.OutOfCapacity, res);
                }
            },
            1 => {
                const got = table.get(id);
                if (ref_alive[idx]) {
                    try testing.expect(got != null);
                    try testing.expectEqual(ref_value[idx], got.?.value);
                    try testing.expectEqual(ref_seen[idx], got.?.last_seen);
                } else {
                    try testing.expect(got == null);
                }
            },
            else => {
                const min_frame: u64 = rand.intRangeLessThan(u64, 0, frame + 1);
                table.prune(min_frame);
                for (0..id_space) |i| {
                    if (ref_alive[i] and ref_seen[i] < min_frame) {
                        ref_alive[i] = false;
                        ref_count -= 1;
                    }
                }
            },
        }
        try testing.expectEqual(ref_count, table.count);
    }
    for (0..id_space) |i| {
        const got = table.get(@as(u64, @intCast(i)));
        if (ref_alive[i]) {
            try testing.expect(got != null);
            try testing.expectEqual(ref_value[i], got.?.value);
            try testing.expectEqual(ref_seen[i], got.?.last_seen);
        } else {
            try testing.expect(got == null);
        }
    }
    try testing.expectEqual(ref_count, table.count);
}

test "failed insertion leaves existing state and frame unchanged" {
    const testing = std.testing;
    var storage: [1]Entry = undefined;
    var table = try Table.init(&storage);
    (try table.getOrPut(7, 3)).value = 99;
    try testing.expectError(error.OutOfCapacity, table.getOrPut(8, 100));
    try testing.expectEqual(@as(usize, 1), table.count);
    try testing.expectEqual(@as(u64, 3), table.get(7).?.last_seen);
    try testing.expectEqual(@as(u64, 99), table.get(7).?.value);
}
