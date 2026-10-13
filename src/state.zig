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

    /// Rebuild in place, removing entries not accessed since min_frame.
    /// O(capacity^2) worst case; invoke only at explicit maintenance points.
    pub fn prune(self: *Table, min_frame: u64) void {
        // Backshift deletion preserves lookup correctness across probe clusters.
        var index: usize = 0;
        while (index < self.entries.len) {
            if (!self.entries[index].occupied or self.entries[index].last_seen >= min_frame) {
                index += 1;
                continue;
            }
            self.entries[index] = .{};
            self.count -= 1;
            var scan = if (index + 1 == self.entries.len) 0 else index + 1;
            while (self.entries[scan].occupied) {
                const saved = self.entries[scan];
                self.entries[scan] = .{};
                self.count -= 1;
                const moved = self.getOrPut(saved.id, saved.last_seen) catch unreachable;
                moved.value = saved.value;
                scan = if (scan + 1 == self.entries.len) 0 else scan + 1;
            }
            // Restart: a displaced entry may now occupy an earlier slot.
            index = 0;
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
