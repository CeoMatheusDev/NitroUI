//! Caller-owned, allocation-free single-line UTF-8 editing primitives.
//! This module does not interpret OS keys, own storage, or render a widget.
const std = @import("std");
const text = @import("text.zig");

pub const Error = error{ InvalidUtf8, InvalidCursor, OutOfCapacity, InvalidScalar };

/// `len` bytes in `storage[0..len]` are valid UTF-8. `cursor` is a byte
/// offset at a scalar boundary, not a grapheme-cluster or visual position.
/// The caller retains ownership of storage and must not mutate it while editing.
pub const Buffer = struct {
    storage: []u8,
    len: usize,
    cursor: usize,
    anchor: ?usize = null,

    pub fn init(storage: []u8, initial: []const u8) Error!Buffer {
        try validate(initial);
        if (initial.len > storage.len) return error.OutOfCapacity;
        // Copy only after validation; overlapping source/destination is forbidden.
        if (overlaps(storage[0..initial.len], initial)) return error.InvalidCursor;
        @memcpy(storage[0..initial.len], initial);
        return .{ .storage = storage, .len = initial.len, .cursor = initial.len };
    }

    pub fn view(self: *const Buffer) []const u8 {
        return self.storage[0..@min(self.len, self.storage.len)];
    }

    pub fn setCursor(self: *Buffer, offset: usize) Error!void {
        try self.check();
        if (offset > self.len or !isBoundary(self.storage[0..self.len], offset)) return error.InvalidCursor;
        self.cursor = offset;
        self.anchor = null;
    }

    /// Selection endpoints are UTF-8 scalar boundaries; end is exclusive.
    pub const Selection = struct { start: usize, end: usize };

    pub fn selection(self: *const Buffer) ?Selection {
        const a = self.anchor orelse return null;
        if (a == self.cursor) return null;
        return .{ .start = @min(a, self.cursor), .end = @max(a, self.cursor) };
    }

    pub fn select(self: *Buffer, anchor: usize, caret: usize) Error!void {
        try self.check();
        const bytes = self.storage[0..self.len];
        if (anchor > self.len or caret > self.len) return error.InvalidCursor;
        if (!isBoundary(bytes, anchor) or !isBoundary(bytes, caret)) return error.InvalidCursor;
        self.anchor = if (anchor == caret) null else anchor;
        self.cursor = caret;
    }

    pub fn clearSelection(self: *Buffer) Error!void {
        try self.check();
        self.anchor = null;
    }

    /// Delete selected bytes, if any. Does not allocate.
    pub fn deleteSelection(self: *Buffer) Error!bool {
        try self.check();
        return self.deleteSelectionPrechecked();
    }

    // Only call after check(): selection boundaries and storage are valid.
    fn deleteSelectionPrechecked(self: *Buffer) bool {
        const range = self.selection() orelse return false;
        self.erase(range.start, range.end);
        self.cursor = range.start;
        self.anchor = null;
        return true;
    }

    /// Replace selection with a scalar, or insert at cursor when no selection.
    /// Capacity and scalar validation happen before any mutation.
    pub fn replaceSelectionScalar(self: *Buffer, scalar: u32) Error!void {
        try self.check();
        if (scalar > 0x10ffff or (scalar >= 0xd800 and scalar <= 0xdfff)) return error.InvalidScalar;
        const size: usize = if (scalar < 0x80) 1 else if (scalar < 0x800) 2 else if (scalar < 0x10000) 3 else 4;
        const range = self.selection() orelse Selection{ .start = self.cursor, .end = self.cursor };
        if (size > self.storage.len - (self.len - (range.end - range.start))) return error.OutOfCapacity;
        if (range.end != range.start) {
            self.erase(range.start, range.end);
            self.cursor = range.start;
        }
        self.anchor = null;
        // State, scalar and final capacity were validated before erase.
        // Avoid rescanning the entire UTF-8 buffer after mutation.
        self.insertScalarPrechecked(scalar, size);
    }

    /// Move caret while extending the selection from its original anchor.
    pub fn moveLeftSelecting(self: *Buffer) Error!bool {
        try self.check();
        if (self.cursor == 0) return false;
        const origin = self.anchor orelse self.cursor;
        var pos = self.cursor - 1;
        while (pos > 0 and (self.storage[pos] & 0xc0) == 0x80) : (pos -= 1) {}
        self.cursor = pos;
        self.anchor = if (origin == pos) null else origin;
        return true;
    }

    pub fn moveRightSelecting(self: *Buffer) Error!bool {
        try self.check();
        if (self.cursor == self.len) return false;
        const origin = self.anchor orelse self.cursor;
        const decoded = text.decodeOne(self.storage[self.cursor..self.len]) catch return error.InvalidUtf8;
        self.cursor += decoded.len;
        self.anchor = if (origin == self.cursor) null else origin;
        return true;
    }

    pub fn moveLeft(self: *Buffer) Error!bool {
        try self.check();
        if (self.cursor == 0) return false;
        var pos = self.cursor - 1;
        while (pos > 0 and (self.storage[pos] & 0xc0) == 0x80) : (pos -= 1) {}
        self.cursor = pos;
        self.anchor = null;
        return true;
    }

    pub fn moveRight(self: *Buffer) Error!bool {
        try self.check();
        if (self.cursor == self.len) return false;
        const decoded = text.decodeOne(self.storage[self.cursor..self.len]) catch return error.InvalidUtf8;
        self.cursor += decoded.len;
        self.anchor = null;
        return true;
    }

    /// Insert exactly one Unicode scalar. Failure preserves all buffer state.
    pub fn insertScalar(self: *Buffer, scalar: u32) Error!void {
        try self.check();
        if (scalar > 0x10ffff or (scalar >= 0xd800 and scalar <= 0xdfff)) return error.InvalidScalar;
        const size: usize = if (scalar < 0x80) 1 else if (scalar < 0x800) 2 else if (scalar < 0x10000) 3 else 4;
        if (size > self.storage.len - self.len) return error.OutOfCapacity;
        self.insertScalarPrechecked(scalar, size);
    }

    /// Internal insertion: caller has validated state, scalar and capacity.
    fn insertScalarPrechecked(self: *Buffer, scalar: u32, size: usize) void {
        var encoded: [4]u8 = undefined;
        switch (size) {
            1 => encoded[0] = @intCast(scalar),
            2 => {
                encoded[0] = @intCast(0xc0 | (scalar >> 6));
                encoded[1] = @intCast(0x80 | (scalar & 0x3f));
            },
            3 => {
                encoded[0] = @intCast(0xe0 | (scalar >> 12));
                encoded[1] = @intCast(0x80 | ((scalar >> 6) & 0x3f));
                encoded[2] = @intCast(0x80 | (scalar & 0x3f));
            },
            4 => {
                encoded[0] = @intCast(0xf0 | (scalar >> 18));
                encoded[1] = @intCast(0x80 | ((scalar >> 12) & 0x3f));
                encoded[2] = @intCast(0x80 | ((scalar >> 6) & 0x3f));
                encoded[3] = @intCast(0x80 | (scalar & 0x3f));
            },
            else => unreachable,
        }
        // Backwards copy permits in-place shifting without an allocator.
        var i = self.len;
        while (i > self.cursor) {
            i -= 1;
            self.storage[i + size] = self.storage[i];
        }
        @memcpy(self.storage[self.cursor..][0..size], encoded[0..size]);
        self.len += size;
        self.cursor += size;
        self.anchor = null;
    }

    pub fn backspace(self: *Buffer) Error!bool {
        try self.check();
        if (self.deleteSelectionPrechecked()) return true;
        if (self.cursor == 0) return false;
        const end = self.cursor;
        var start = end - 1;
        while (start > 0 and (self.storage[start] & 0xc0) == 0x80) : (start -= 1) {}
        self.erase(start, end);
        self.cursor = start;
        self.anchor = null;
        return true;
    }

    pub fn deleteForward(self: *Buffer) Error!bool {
        try self.check();
        if (self.deleteSelectionPrechecked()) return true;
        if (self.cursor == self.len) return false;
        const decoded = text.decodeOne(self.storage[self.cursor..self.len]) catch return error.InvalidUtf8;
        self.erase(self.cursor, self.cursor + decoded.len);
        self.anchor = null;
        return true;
    }

    fn erase(self: *Buffer, start: usize, end: usize) void {
        const removed = end - start;
        var i = end;
        while (i < self.len) : (i += 1) self.storage[i - removed] = self.storage[i];
        self.len -= removed;
    }

    /// Validate caller-owned storage, UTF-8 and selection offsets without mutation.
    /// Useful before beginning fallible widget interaction/rendering.
    pub fn validateState(self: *const Buffer) Error!void {
        try self.check();
    }

    fn check(self: *const Buffer) Error!void {
        if (self.len > self.storage.len) return error.OutOfCapacity;
        try validate(self.storage[0..self.len]);
        if (self.cursor > self.len or !isBoundary(self.storage[0..self.len], self.cursor)) return error.InvalidCursor;
        if (self.anchor) |a| {
            if (a > self.len or !isBoundary(self.storage[0..self.len], a)) return error.InvalidCursor;
        }
    }
};

fn validate(bytes: []const u8) Error!void {
    var i: usize = 0;
    while (i < bytes.len) {
        const d = text.decodeOne(bytes[i..]) catch return error.InvalidUtf8;
        i += d.len;
    }
}

fn isBoundary(bytes: []const u8, index: usize) bool {
    return index == bytes.len or (bytes[index] & 0xc0) != 0x80;
}

fn overlaps(a: []const u8, b: []const u8) bool {
    if (a.len == 0 or b.len == 0) return false;
    const x = @intFromPtr(a.ptr);
    const y = @intFromPtr(b.ptr);
    const xe = std.math.add(usize, x, a.len) catch return true;
    const ye = std.math.add(usize, y, b.len) catch return true;
    return x < ye and y < xe;
}

test "stage28_57 replacement across multibyte suffix uses exact capacity" {
    const t = std.testing;
    var storage: [9]u8 = undefined;
    var editor = try Buffer.init(&storage, "aX€b");
    try editor.select(2, 1);
    try editor.replaceSelectionScalar(0x1f680);
    try t.expectEqualStrings("a🚀€b", editor.view());
    try t.expectEqual(@as(usize, 9), editor.len);
    try t.expectEqual(@as(usize, 5), editor.cursor);
    try t.expect(editor.selection() == null);
    try editor.validateState();
}

test "stage28_57 failed replacement remains atomic before successful retry" {
    const t = std.testing;
    var storage = [_]u8{ 'a', 'b', 'c', 0xaa };
    var editor = try Buffer.init(&storage, "abc");
    try editor.select(1, 3);
    const before = storage;
    try t.expectError(error.OutOfCapacity, editor.replaceSelectionScalar(0x1f680));
    try t.expectEqualSlices(u8, &before, &storage);
    try t.expectEqual(@as(usize, 1), editor.anchor.?);
    try t.expectEqual(@as(usize, 3), editor.cursor);
    try editor.replaceSelectionScalar('Z');
    try t.expectEqualStrings("aZ", editor.view());
    try editor.validateState();
}

test "UTF-8 editing across one to four byte scalars" {
    const t = std.testing;
    var bytes: [32]u8 = undefined;
    var b = try Buffer.init(&bytes, "A€😀");
    try t.expectEqual(@as(usize, 8), b.cursor);
    try t.expect(try b.moveLeft());
    try t.expectEqual(@as(usize, 4), b.cursor);
    try t.expect(try b.backspace());
    try t.expectEqualStrings("A😀", b.view());
    try b.insertScalar(0x20ac);
    try t.expectEqualStrings("A€😀", b.view());
    try t.expect(try b.deleteForward());
    try t.expectEqualStrings("A€", b.view());
    try t.expect(!(try b.deleteForward()));
    try b.setCursor(0);
    try t.expect(!(try b.moveLeft()));
    try t.expect(try b.moveRight());
    try t.expectEqual(@as(usize, 1), b.cursor);
}

test "editing rejects invalid scalars and capacity atomically" {
    const t = std.testing;
    var bytes: [4]u8 = undefined;
    var b = try Buffer.init(&bytes, "A");
    try t.expectError(error.InvalidScalar, b.insertScalar(0xd800));
    try t.expectError(error.InvalidScalar, b.insertScalar(0x110000));
    try t.expectError(error.OutOfCapacity, b.insertScalar(0x1f600));
    try t.expectEqualStrings("A", b.view());
    try t.expectEqual(@as(usize, 1), b.cursor);
    try b.insertScalar(0x20ac);
    try t.expectEqualStrings("A€", b.view());
    try t.expectError(error.OutOfCapacity, b.insertScalar('B'));
    try t.expectEqualStrings("A€", b.view());
}

test "invalid UTF-8 and mid-scalar cursor are rejected" {
    const t = std.testing;
    var bytes: [16]u8 = undefined;
    try t.expectError(error.InvalidUtf8, Buffer.init(&bytes, &.{ 0xc0, 0x80 }));
    var b = try Buffer.init(&bytes, "€Z");
    try t.expectError(error.InvalidCursor, b.setCursor(1));
    try t.expectEqual(@as(usize, 4), b.cursor);
    try b.setCursor(3);
    try t.expect(try b.backspace());
    try t.expectEqualStrings("Z", b.view());
}

test "selection boundaries and atomic replacement" {
    const t = std.testing;
    var bytes: [8]u8 = undefined;
    var b = try Buffer.init(&bytes, "A€😀");
    try b.select(1, 4);
    const range = b.selection().?;
    try t.expectEqual(@as(usize, 1), range.start);
    try t.expectEqual(@as(usize, 4), range.end);
    try t.expectError(error.InvalidCursor, b.select(2, 4));
    try t.expectEqual(@as(usize, 4), b.cursor);
    try t.expectError(error.OutOfCapacity, b.replaceSelectionScalar(0x1f600));
    try t.expectEqualStrings("A€😀", b.view());
    try t.expect(b.selection() != null);
    try b.replaceSelectionScalar('Z');
    try t.expectEqualStrings("AZ😀", b.view());
    try t.expect(b.selection() == null);
}

test "reverse selection, deletion, and selecting movement" {
    const t = std.testing;
    var bytes: [32]u8 = undefined;
    var b = try Buffer.init(&bytes, "a€b");
    try b.select(5, 1);
    try t.expect(try b.backspace());
    try t.expectEqualStrings("a", b.view());
    try t.expectEqual(@as(usize, 1), b.cursor);
    try t.expect(try b.moveLeftSelecting());
    try t.expectEqual(@as(usize, 0), b.selection().?.start);
    try t.expect(try b.moveRightSelecting());
    try t.expect(b.selection() == null);
    try b.select(0, 1);
    try t.expect(try b.deleteForward());
    try t.expectEqualStrings("", b.view());
}

test "shift movement at text boundaries preserves selection and anchor" {
    const t = std.testing;
    var storage: [16]u8 = undefined;
    var editor = try Buffer.init(&storage, "a€b");

    // A reverse selection whose caret is already at the beginning.
    try editor.select(4, 0);
    try t.expect(!(try editor.moveLeftSelecting()));
    try t.expectEqual(@as(usize, 4), editor.anchor.?);
    try t.expectEqual(@as(usize, 0), editor.cursor);
    try t.expectEqual(@as(usize, 0), editor.selection().?.start);
    try t.expectEqual(@as(usize, 4), editor.selection().?.end);

    // Continue selecting from the same anchor, across the multi-byte scalar.
    try t.expect(try editor.moveRightSelecting());
    try t.expectEqual(@as(usize, 4), editor.anchor.?);
    try t.expectEqual(@as(usize, 1), editor.cursor);
    try t.expect(try editor.moveRightSelecting());
    try t.expect(editor.selection() == null);

    // Forward selection whose caret is already at the end.
    try editor.select(1, editor.len);
    try t.expect(!(try editor.moveRightSelecting()));
    try t.expectEqual(@as(usize, 1), editor.anchor.?);
    try t.expectEqual(editor.len, editor.cursor);
    try t.expectEqual(@as(usize, 1), editor.selection().?.start);
    try t.expectEqual(editor.len, editor.selection().?.end);
}

test "externally invalidated UTF-8 and selection are rejected before mutation" {
    const t = std.testing;
    var storage: [16]u8 = undefined;
    var editor = try Buffer.init(&storage, "a€b");
    try editor.select(1, 4);
    storage[1] = 0xff;
    try t.expectError(error.InvalidUtf8, editor.replaceSelectionScalar('X'));
    try t.expectEqual(@as(usize, 5), editor.len);
    try t.expectEqual(@as(usize, 4), editor.cursor);
    try t.expectEqual(@as(usize, 1), editor.anchor.?);
    storage[1] = 0xe2;
    editor.anchor = 2; // Invalid byte boundary, even though UTF-8 is valid.
    try t.expectError(error.InvalidCursor, editor.deleteSelection());
    try t.expectEqualStrings("a€b", editor.view());
}

test "validateState rejects externally invalidated editor without mutation" {
    const t = std.testing;
    var storage: [16]u8 = undefined;
    var editor = try Buffer.init(&storage, "abc");
    try editor.validateState();
    editor.anchor = 9;
    try t.expectError(error.InvalidCursor, editor.validateState());
    try t.expectEqualStrings("abc", editor.view());
    editor.anchor = null;
    storage[1] = 0xff;
    try t.expectError(error.InvalidUtf8, editor.validateState());
    try t.expectEqual(@as(usize, 3), editor.len);
}

test "stage28_36 exact-capacity multibyte replacement preserves UTF-8 boundaries" {
    const t = std.testing;
    var storage: [6]u8 = undefined;
    var editor = try Buffer.init(&storage, "a€b");
    // Reverse selection: caret before the three-byte scalar and 'b'.
    try editor.select(5, 1);
    try editor.replaceSelectionScalar(0x1f680); // Four-byte rocket, exact capacity.
    try t.expectEqualStrings("a🚀", editor.view());
    try t.expectEqual(@as(usize, 5), editor.len);
    try t.expectEqual(@as(usize, 5), editor.cursor);
    try t.expect(editor.selection() == null);
    try editor.validateState();

    // A subsequent insertion cannot fit; the valid editor remains unchanged.
    try t.expectError(error.OutOfCapacity, editor.insertScalar(0x20ac));
    try t.expectEqualStrings("a🚀", editor.view());
    try t.expectEqual(@as(usize, 5), editor.cursor);
    try editor.validateState();
}

test "stage28_48 initialization rejects overlapping input without modifying caller storage" {
    const t = std.testing;
    var storage = [_]u8{ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h' };
    const before = storage;

    // The source aliases the destination even though its beginning differs.
    try t.expectError(error.InvalidCursor, Buffer.init(storage[0..], storage[2..5]));
    try t.expectEqualSlices(u8, &before, &storage);

    // Exact aliasing is rejected as well: initialization never relies on memcpy overlap.
    try t.expectError(error.InvalidCursor, Buffer.init(storage[0..], storage[0..3]));
    try t.expectEqualSlices(u8, &before, &storage);

    // Nonoverlapping caller storage is accepted and copied into the destination.
    const editor = try Buffer.init(storage[0..], "XYZ");
    try t.expectEqualStrings("XYZ", editor.view());
    try t.expectEqual(@as(usize, 3), editor.cursor);
}

test "stage28_49 empty initialization accepts zero-length alias and preserves storage" {
    const t = std.testing;
    var storage = [_]u8{ 'A', 'B', 'C', 'D' };
    const before = storage;

    // No bytes are read or copied: a zero-length alias is not an overlapping range.
    const editor = try Buffer.init(storage[0..], storage[2..2]);
    try t.expectEqual(@as(usize, 0), editor.len);
    try t.expectEqual(@as(usize, 0), editor.cursor);
    try t.expect(editor.anchor == null);
    try t.expectEqualStrings("", editor.view());
    try t.expectEqualSlices(u8, &before, &storage);
    try editor.validateState();
}

test "stage28_49 failed initialization preserves caller bytes and accepts exact capacity" {
    const t = std.testing;
    var storage = [_]u8{ 0xaa, 0xbb, 0xcc, 0xdd };
    const before = storage;

    try t.expectError(error.OutOfCapacity, Buffer.init(storage[0..], "abcde"));
    try t.expectEqualSlices(u8, &before, &storage);
    try t.expectError(error.InvalidUtf8, Buffer.init(storage[0..], &[_]u8{0xff}));
    try t.expectEqualSlices(u8, &before, &storage);

    const editor = try Buffer.init(storage[0..], "a€");
    try t.expectEqualStrings("a€", editor.view());
    try t.expectEqual(@as(usize, 4), editor.len);
    try t.expectEqual(@as(usize, 4), editor.cursor);
    try editor.validateState();
}

test "stage28_50 failed replacement retains reverse selection for smaller retry" {
    const t = std.testing;
    var storage = [_]u8{ 0, 0, 0, 0, 0, 0 };
    var editor = try Buffer.init(&storage, "a€b");
    try editor.select(5, 4); // Reverse selection of the final ASCII byte.
    const before = storage;

    // Replacing one byte with a four-byte scalar exceeds six bytes.
    try t.expectError(error.OutOfCapacity, editor.replaceSelectionScalar(0x1f680));
    try t.expectEqualSlices(u8, &before, &storage);
    try t.expectEqualStrings("a€b", editor.view());
    try t.expectEqual(@as(usize, 5), editor.anchor.?);
    try t.expectEqual(@as(usize, 4), editor.cursor);
    try editor.validateState();

    // The application can retry with a scalar that fits without reselecting.
    try editor.replaceSelectionScalar('Z');
    try t.expectEqualStrings("a€Z", editor.view());
    try t.expectEqual(@as(usize, 5), editor.cursor);
    try t.expect(editor.anchor == null);
    try editor.validateState();
}

// Overlap is defined against the destination bytes actually written, not the
// entire caller-owned capacity. A source in the unused tail is safe to copy.
test "stage28_51 initialization accepts disjoint source in unused storage tail" {
    const t = std.testing;
    var storage = [_]u8{ 'X', 'X', 'X', 'X', 'a', 0xe2, 0x82, 0xac };
    const initial = storage[4..8];
    var editor = try Buffer.init(&storage, initial);
    try t.expectEqualStrings("a€", editor.view());
    try t.expectEqual(@as(usize, 4), editor.len);
    try t.expectEqual(@as(usize, 4), editor.cursor);
    try t.expect(editor.selection() == null);
    try editor.validateState();
    try t.expectEqualSlices(u8, "a€", storage[4..8]);

    // Writing into the source region itself is not permitted.
    const before = storage;
    try t.expectError(error.InvalidCursor, Buffer.init(storage[0..4], storage[1..4]));
    try t.expectEqualSlices(u8, &before, &storage);
}

// Invalid Unicode scalars must be rejected before deleting an active selection.
test "stage28_52 invalid scalar preserves selected UTF-8 and allows retry" {
    const t = std.testing;
    var storage: [12]u8 = @splat(0xaa);
    var editor = try Buffer.init(&storage, "a€b");
    try editor.select(4, 1); // Reverse selection of the three-byte euro sign.
    const before = storage;

    try t.expectError(error.InvalidScalar, editor.replaceSelectionScalar(0xd800));
    try t.expectEqualSlices(u8, &before, &storage);
    try t.expectEqualStrings("a€b", editor.view());
    try t.expectEqual(@as(usize, 4), editor.anchor.?);
    try t.expectEqual(@as(usize, 1), editor.cursor);
    try editor.validateState();

    try t.expectError(error.InvalidScalar, editor.replaceSelectionScalar(0x110000));
    try t.expectEqualSlices(u8, &before, &storage);
    try t.expectEqual(@as(usize, 4), editor.anchor.?);
    try t.expectEqual(@as(usize, 1), editor.cursor);

    try editor.replaceSelectionScalar(0x1f680); // Four-byte rocket replaces euro.
    try t.expectEqualStrings("a🚀b", editor.view());
    try t.expectEqual(@as(usize, 5), editor.cursor);
    try t.expect(editor.anchor == null);
    try editor.validateState();
}

// Replacing a shorter selection with a longer scalar must shift the untouched
// suffix to the right without corrupting any UTF-8 scalar boundary.
test "stage28_53 growing replacement preserves multibyte suffix at exact capacity" {
    const t = std.testing;
    var storage: [9]u8 = @splat(0xa5);
    var editor = try Buffer.init(&storage, "aX€b"); // 6 bytes.
    try editor.select(2, 1); // Reverse selection of X.
    try editor.replaceSelectionScalar(0x1f680); // Four-byte rocket.

    try t.expectEqualStrings("a🚀€b", editor.view());
    try t.expectEqual(@as(usize, 9), editor.len);
    try t.expectEqual(@as(usize, 5), editor.cursor);
    try t.expect(editor.anchor == null);
    try editor.validateState();

    // The suffix remains navigable at scalar, not byte, boundaries.
    try t.expect(try editor.moveRight());
    try t.expectEqual(@as(usize, 8), editor.cursor);
    try t.expect(try editor.moveRight());
    try t.expectEqual(@as(usize, 9), editor.cursor);
    try t.expect(!(try editor.moveRight()));
    try t.expectEqualStrings("a🚀€b", editor.view());
}

// The caller owns the editor structure. A corrupted logical length must be
// rejected before slicing storage or writing, and may be repaired explicitly.
test "stage28_54 oversized logical length rejects edits and permits caller repair" {
    const t = std.testing;
    var storage: [8]u8 = @splat(0xa5);
    var editor = try Buffer.init(&storage, "abc");
    const before = storage;
    editor.len = storage.len + 1;

    try t.expectError(error.OutOfCapacity, editor.validateState());
    try t.expectError(error.OutOfCapacity, editor.insertScalar('Z'));
    try t.expectError(error.OutOfCapacity, editor.replaceSelectionScalar('Z'));
    try t.expectError(error.OutOfCapacity, editor.backspace());
    try t.expectEqualSlices(u8, &before, &storage);
    try t.expectEqual(@as(usize, 3), editor.cursor);
    try t.expect(editor.anchor == null);

    // Repair belongs to the engine; no implicit truncation is performed.
    editor.len = 3;
    try editor.validateState();
    try editor.insertScalar('Z');
    try t.expectEqualStrings("abcZ", editor.view());
    try t.expectEqual(@as(usize, 4), editor.cursor);
    try editor.validateState();
}

// The engine may mutate its own storage between frames. Editing must detect
// malformed UTF-8 before shifting bytes, and allow an explicit caller repair.
test "stage28_55 externally corrupted UTF-8 rejects edits and permits repair" {
    const t = std.testing;
    var storage: [12]u8 = @splat(0xa5);
    var editor = try Buffer.init(&storage, "a€b");
    try editor.setCursor(1);

    // Break the continuation byte of the three-byte euro scalar.
    storage[2] = 'X';
    const corrupted = storage;
    try t.expectError(error.InvalidUtf8, editor.validateState());
    try t.expectError(error.InvalidUtf8, editor.insertScalar('Z'));
    try t.expectError(error.InvalidUtf8, editor.replaceSelectionScalar('Z'));
    try t.expectError(error.InvalidUtf8, editor.deleteForward());
    try t.expectEqualSlices(u8, &corrupted, &storage);
    try t.expectEqual(@as(usize, 5), editor.len);
    try t.expectEqual(@as(usize, 1), editor.cursor);
    try t.expect(editor.anchor == null);

    // Only the caller restores the storage. The editor then resumes normally.
    storage[2] = 0x82;
    try editor.validateState();
    try t.expect(try editor.deleteForward());
    try t.expectEqualStrings("ab", editor.view());
    try t.expectEqual(@as(usize, 1), editor.cursor);
    try editor.validateState();
}

// Backspace and forward deletion validate once, then operate on prechecked
// scalar boundaries. Both must retain selection semantics and UTF-8 integrity.
test "stage28_58 backspace removes preceding scalar and keeps suffix" {
    const t = std.testing;
    var storage: [12]u8 = @splat(0xa5);
    var editor = try Buffer.init(&storage, "a€🚀b");
    try editor.setCursor(8); // immediately after the four-byte rocket
    try t.expect(try editor.backspace());
    try t.expectEqualStrings("a€b", editor.view());
    try t.expectEqual(@as(usize, 4), editor.cursor);
    try editor.validateState();
    try t.expect(try editor.backspace());
    try t.expectEqualStrings("ab", editor.view());
    try t.expectEqual(@as(usize, 1), editor.cursor);
    try editor.validateState();
}

test "stage28_58 deletion of reverse selection preserves scalar boundaries" {
    const t = std.testing;
    var storage: [12]u8 = @splat(0xa5);
    var editor = try Buffer.init(&storage, "a€🚀b");
    try editor.select(8, 1);
    try t.expect(try editor.deleteForward());
    try t.expectEqualStrings("ab", editor.view());
    try t.expectEqual(@as(usize, 1), editor.cursor);
    try t.expect(editor.selection() == null);
    try editor.validateState();
    try t.expect(try editor.deleteForward());
    try t.expectEqualStrings("a", editor.view());
    try editor.validateState();
}

// Moving a selection across multibyte scalars must preserve its original anchor.
test "stage28_59 selecting movement retains anchor and clears on return" {
    const t = std.testing;
    var storage: [16]u8 = undefined;
    var editor = try Buffer.init(&storage, "a€🚀b");
    try editor.setCursor(4);
    try t.expect(try editor.moveRightSelecting());
    try t.expectEqual(@as(usize, 8), editor.cursor);
    try t.expectEqual(@as(?usize, 4), editor.anchor);
    try t.expect(try editor.moveRightSelecting());
    try t.expectEqual(@as(usize, 9), editor.cursor);
    try t.expectEqual(@as(?usize, 4), editor.anchor);
    try t.expect(!try editor.moveRightSelecting());
    try t.expectEqual(@as(?usize, 4), editor.anchor);
    try t.expect(try editor.moveLeftSelecting());
    try t.expectEqual(@as(usize, 8), editor.cursor);
    try t.expect(try editor.moveLeftSelecting());
    try t.expectEqual(@as(usize, 4), editor.cursor);
    try t.expect(editor.anchor == null);
    try t.expect(editor.selection() == null);
    try editor.validateState();
}

test "stage28_59 selecting movement rejects invalid UTF-8 without mutation" {
    const t = std.testing;
    var storage: [8]u8 = undefined;
    var editor = try Buffer.init(&storage, "a€b");
    try editor.setCursor(1);
    storage[2] = 0x58;
    const before = storage;
    try t.expectError(error.InvalidUtf8, editor.moveRightSelecting());
    try t.expectError(error.InvalidUtf8, editor.moveLeftSelecting());
    try t.expectEqual(@as(usize, 1), editor.cursor);
    try t.expect(editor.anchor == null);
    try t.expectEqualSlices(u8, &before, &storage);
}

// Exhaustive short ASCII edit sequences against an independent fixed-array model.
// No allocator or engine backend is involved.
test "stage28_60 exhaustive short edit sequences agree with ASCII reference" {
    const t = std.testing;
    const operations: usize = 5; // insert, left, right, backspace, delete-forward
    const steps: usize = 5;
    const cases: usize = 3125; // 5^5
    var sequence: usize = 0;
    while (sequence < cases) : (sequence += 1) {
        var storage: [16]u8 = undefined;
        var editor = try Buffer.init(&storage, "ab");
        var expected: [16]u8 = undefined;
        expected[0] = 'a';
        expected[1] = 'b';
        var len: usize = 2;
        var cursor: usize = 2;
        var encoded = sequence;
        var step: usize = 0;
        while (step < steps) : (step += 1) {
            const op = encoded % operations;
            encoded /= operations;
            switch (op) {
                0 => {
                    try editor.insertScalar('X');
                    var i = len;
                    while (i > cursor) {
                        i -= 1;
                        expected[i + 1] = expected[i];
                    }
                    expected[cursor] = 'X';
                    len += 1;
                    cursor += 1;
                },
                1 => {
                    const moved = cursor != 0;
                    try t.expectEqual(moved, try editor.moveLeft());
                    if (moved) cursor -= 1;
                },
                2 => {
                    const moved = cursor != len;
                    try t.expectEqual(moved, try editor.moveRight());
                    if (moved) cursor += 1;
                },
                3 => {
                    const removed = cursor != 0;
                    try t.expectEqual(removed, try editor.backspace());
                    if (removed) {
                        var i = cursor;
                        while (i < len) : (i += 1) expected[i - 1] = expected[i];
                        len -= 1;
                        cursor -= 1;
                    }
                },
                4 => {
                    const removed = cursor != len;
                    try t.expectEqual(removed, try editor.deleteForward());
                    if (removed) {
                        var i = cursor + 1;
                        while (i < len) : (i += 1) expected[i - 1] = expected[i];
                        len -= 1;
                    }
                },
                else => unreachable,
            }
            try t.expectEqualSlices(u8, expected[0..len], editor.view());
            try t.expectEqual(len, editor.len);
            try t.expectEqual(cursor, editor.cursor);
            try t.expect(editor.selection() == null);
            try editor.validateState();
        }
    }
}

// Model cursor positions as scalar indices independently of UTF-8 byte offsets.
// This catches accidental continuation-byte navigation after mixed-width edits.
test "stage28_61 exhaustive mixed-width scalar navigation and deletion" {
    const t = std.testing;
    const initial = "a€🚀b";
    const widths = [_]usize{ 1, 3, 4, 1 };
    const cases: usize = 1024; // 4^5 sequences
    var sequence: usize = 0;
    while (sequence < cases) : (sequence += 1) {
        var storage: [16]u8 = undefined;
        var editor = try Buffer.init(&storage, initial);
        var expected_widths = widths;
        var count: usize = widths.len;
        var caret: usize = count;
        var encoded = sequence;
        for (0..5) |_| {
            const op = encoded % 4;
            encoded /= 4;
            switch (op) {
                0 => {
                    const moved = caret > 0;
                    try t.expectEqual(moved, try editor.moveLeft());
                    if (moved) caret -= 1;
                },
                1 => {
                    const moved = caret < count;
                    try t.expectEqual(moved, try editor.moveRight());
                    if (moved) caret += 1;
                },
                2 => {
                    const removed = caret > 0;
                    try t.expectEqual(removed, try editor.backspace());
                    if (removed) {
                        var i = caret;
                        while (i < count) : (i += 1) expected_widths[i - 1] = expected_widths[i];
                        count -= 1;
                        caret -= 1;
                    }
                },
                3 => {
                    const removed = caret < count;
                    try t.expectEqual(removed, try editor.deleteForward());
                    if (removed) {
                        var i = caret + 1;
                        while (i < count) : (i += 1) expected_widths[i - 1] = expected_widths[i];
                        count -= 1;
                    }
                },
                else => unreachable,
            }
            var expected_len: usize = 0;
            var expected_cursor: usize = 0;
            for (expected_widths[0..count], 0..) |width, index| {
                if (index < caret) expected_cursor += width;
                expected_len += width;
            }
            try t.expectEqual(expected_len, editor.len);
            try t.expectEqual(expected_cursor, editor.cursor);
            try t.expect(editor.selection() == null);
            try editor.validateState();
        }
    }
}

// Independent scalar-level oracle checks actual bytes, not just UTF-8 widths.
test "stage28_62 mixed-width insertion and deletion match scalar oracle" {
    const t = std.testing;
    const initial = [_]u8{ 0x61, 0xe2, 0x82, 0xac, 0x62 }; // a€b
    var sequence: usize = 0;
    while (sequence < 256) : (sequence += 1) { // 4^4 sequences
        var storage: [24]u8 = undefined;
        var editor = try Buffer.init(&storage, &initial);
        var model = [_]u32{ 'a', 0x20ac, 'b', 0, 0, 0, 0 };
        var count: usize = 3;
        var caret: usize = 3;
        var encoded = sequence;
        for (0..4) |_| {
            const op = encoded % 4;
            encoded /= 4;
            switch (op) {
                0 => {
                    try editor.insertScalar(0x1f680);
                    var i = count;
                    while (i > caret) {
                        i -= 1;
                        model[i + 1] = model[i];
                    }
                    model[caret] = 0x1f680;
                    count += 1;
                    caret += 1;
                },
                1 => {
                    try t.expectEqual(caret > 0, try editor.moveLeft());
                    if (caret > 0) caret -= 1;
                },
                2 => {
                    try t.expectEqual(caret > 0, try editor.backspace());
                    if (caret > 0) {
                        var i = caret;
                        while (i < count) : (i += 1) model[i - 1] = model[i];
                        count -= 1;
                        caret -= 1;
                    }
                },
                3 => {
                    try t.expectEqual(caret < count, try editor.deleteForward());
                    if (caret < count) {
                        var i = caret + 1;
                        while (i < count) : (i += 1) model[i - 1] = model[i];
                        count -= 1;
                    }
                },
                else => unreachable,
            }
            var expected: [24]u8 = undefined;
            var len: usize = 0;
            var cursor: usize = 0;
            for (model[0..count], 0..) |scalar, index| {
                const bytes: []const u8 = switch (scalar) {
                    'a' => "a",
                    'b' => "b",
                    0x20ac => "€",
                    0x1f680 => "🚀",
                    else => unreachable,
                };
                @memcpy(expected[len..][0..bytes.len], bytes);
                len += bytes.len;
                if (index < caret) cursor += bytes.len;
            }
            try t.expectEqualSlices(u8, expected[0..len], editor.view());
            try t.expectEqual(cursor, editor.cursor);
            try t.expect(editor.selection() == null);
            try editor.validateState();
        }
    }
}

test "stage28_63 all scalar-boundary selections replace atomically against byte oracle" {
    const t = std.testing;
    const initial = "a€🚀b";
    const offsets = [_]usize{ 0, 1, 4, 8, 9 };
    const replacements = [_]struct { scalar: u32, bytes: []const u8 }{
        .{ .scalar = 'Z', .bytes = "Z" },
        .{ .scalar = 0x20ac, .bytes = "€" },
        .{ .scalar = 0x1f680, .bytes = "🚀" },
    };
    for (offsets) |anchor| {
        for (offsets) |caret| {
            for (replacements) |replacement| {
                var storage: [12]u8 = @splat(0xa5);
                var editor = try Buffer.init(&storage, initial);
                try editor.select(anchor, caret);
                const before = storage;
                const start = @min(anchor, caret);
                const end = @max(anchor, caret);
                const expected_len = start + replacement.bytes.len + initial.len - end;
                if (expected_len > storage.len) {
                    try t.expectError(error.OutOfCapacity, editor.replaceSelectionScalar(replacement.scalar));
                    try t.expectEqualSlices(u8, &before, &storage);
                    try t.expectEqual(@as(usize, initial.len), editor.len);
                    try t.expectEqual(caret, editor.cursor);
                    try t.expectEqual(if (anchor == caret) @as(?usize, null) else @as(?usize, anchor), editor.anchor);
                } else {
                    var expected: [12]u8 = undefined;
                    @memcpy(expected[0..start], initial[0..start]);
                    @memcpy(expected[start..][0..replacement.bytes.len], replacement.bytes);
                    @memcpy(expected[start + replacement.bytes.len ..][0 .. initial.len - end], initial[end..]);
                    try editor.replaceSelectionScalar(replacement.scalar);
                    try t.expectEqualSlices(u8, expected[0..expected_len], editor.view());
                    try t.expectEqual(expected_len, editor.len);
                    try t.expectEqual(start + replacement.bytes.len, editor.cursor);
                    try t.expect(editor.anchor == null);
                }
                try editor.validateState();
            }
        }
    }
}

test "stage28_64 scalar encoding boundaries match exact UTF-8 bytes" {
    const t = std.testing;
    const cases = [_]struct { scalar: u32, bytes: []const u8 }{
        .{ .scalar = 0x00, .bytes = "\x00" },
        .{ .scalar = 0x7f, .bytes = "\x7f" },
        .{ .scalar = 0x80, .bytes = "\xc2\x80" },
        .{ .scalar = 0x7ff, .bytes = "\xdf\xbf" },
        .{ .scalar = 0x800, .bytes = "\xe0\xa0\x80" },
        .{ .scalar = 0xd7ff, .bytes = "\xed\x9f\xbf" },
        .{ .scalar = 0xe000, .bytes = "\xee\x80\x80" },
        .{ .scalar = 0xffff, .bytes = "\xef\xbf\xbf" },
        .{ .scalar = 0x10000, .bytes = "\xf0\x90\x80\x80" },
        .{ .scalar = 0x10ffff, .bytes = "\xf4\x8f\xbf\xbf" },
    };
    for (cases) |case| {
        var storage: [8]u8 = @splat(0xa5);
        var editor = try Buffer.init(&storage, "ab");
        try editor.setCursor(1);
        try editor.insertScalar(case.scalar);
        var expected: [6]u8 = undefined;
        expected[0] = 'a';
        @memcpy(expected[1..][0..case.bytes.len], case.bytes);
        expected[1 + case.bytes.len] = 'b';
        try t.expectEqualSlices(u8, expected[0 .. case.bytes.len + 2], editor.view());
        try t.expectEqual(@as(usize, 1) + case.bytes.len, editor.cursor);
        try editor.validateState();
    }
}

test "stage28_64 rejected Unicode scalar leaves selection and bytes unchanged" {
    const t = std.testing;
    const invalid = [_]u32{ 0xd800, 0xdfff, 0x110000, 0xffffffff };
    for (invalid) |scalar| {
        var storage: [8]u8 = @splat(0xa5);
        var editor = try Buffer.init(&storage, "a€b");
        try editor.select(4, 1);
        const before = storage;
        try t.expectError(error.InvalidScalar, editor.replaceSelectionScalar(scalar));
        try t.expectEqualSlices(u8, &before, &storage);
        try t.expectEqual(@as(usize, 5), editor.len);
        try t.expectEqual(@as(usize, 1), editor.cursor);
        try t.expectEqual(@as(?usize, 4), editor.anchor);
        try editor.validateState();
    }
}

test "stage28_65 rejected selection endpoints preserve reverse selection and storage" {
    const t = std.testing;
    var storage: [12]u8 = @splat(0xa5);
    var editor = try Buffer.init(&storage, "a€🚀b");
    try editor.select(8, 1);
    const before = storage;
    const invalid = [_]struct { anchor: usize, caret: usize }{
        .{ .anchor = 2, .caret = 1 }, // Inside the three-byte scalar.
        .{ .anchor = 1, .caret = 6 }, // Inside the four-byte scalar.
        .{ .anchor = 10, .caret = 1 }, // Beyond logical text length.
        .{ .anchor = 8, .caret = 12 }, // Capacity is not logical text length.
    };
    for (invalid) |endpoints| {
        try t.expectError(error.InvalidCursor, editor.select(endpoints.anchor, endpoints.caret));
        try t.expectEqualSlices(u8, &before, &storage);
        try t.expectEqual(@as(usize, 9), editor.len);
        try t.expectEqual(@as(usize, 1), editor.cursor);
        try t.expectEqual(@as(?usize, 8), editor.anchor);
        try editor.validateState();
    }
    try editor.select(4, 9);
    try t.expectEqual(@as(usize, 9), editor.cursor);
    try t.expectEqual(@as(?usize, 4), editor.anchor);
    try t.expectEqualSlices(u8, &before, &storage);
    try editor.validateState();
}

test "stage28_66 setCursor rejects every non-boundary without clearing selection" {
    const t = std.testing;
    var storage: [12]u8 = @splat(0xa5);
    var editor = try Buffer.init(&storage, "a€🚀b");
    try editor.select(8, 1);
    const before = storage;
    // Exhaustively probe all offsets within the logical text and two
    // out-of-range offsets, including the maximum representable usize.
    const invalid = [_]usize{ 2, 3, 5, 6, 7, 10, 12, std.math.maxInt(usize) };
    for (invalid) |offset| {
        try t.expectError(error.InvalidCursor, editor.setCursor(offset));
        try t.expectEqualSlices(u8, &before, &storage);
        try t.expectEqual(@as(usize, 9), editor.len);
        try t.expectEqual(@as(usize, 1), editor.cursor);
        try t.expectEqual(@as(?usize, 8), editor.anchor);
        try editor.validateState();
    }
    // Every scalar boundary is accepted and clears the previous selection.
    const valid = [_]usize{ 0, 1, 4, 8, 9 };
    for (valid) |offset| {
        try editor.select(8, 1);
        try editor.setCursor(offset);
        try t.expectEqual(offset, editor.cursor);
        try t.expect(editor.anchor == null);
        try t.expectEqualSlices(u8, &before, &storage);
        try editor.validateState();
    }
}

// A caller can construct a valid collapsed anchor because Buffer fields are
// public. Deletion must not accidentally turn that into a new selection.
test "stage28_67 backspace clears collapsed anchor after deleting multibyte scalar" {
    const t = std.testing;
    var storage: [16]u8 = undefined;
    var editor = try Buffer.init(&storage, "a€b");
    editor.anchor = editor.cursor;
    try editor.validateState();
    try t.expect(try editor.backspace());
    try t.expectEqualStrings("a€", editor.view());
    try t.expectEqual(@as(usize, 4), editor.cursor);
    try t.expect(editor.anchor == null);
    try t.expect(editor.selection() == null);
    try editor.validateState();
}

test "stage28_67 deleteForward clears collapsed anchor after deleting multibyte scalar" {
    const t = std.testing;
    var storage: [16]u8 = undefined;
    var editor = try Buffer.init(&storage, "a€b");
    try editor.setCursor(1);
    editor.anchor = editor.cursor;
    try editor.validateState();
    try t.expect(try editor.deleteForward());
    try t.expectEqualStrings("ab", editor.view());
    try t.expectEqual(@as(usize, 1), editor.cursor);
    try t.expect(editor.anchor == null);
    try t.expect(editor.selection() == null);
    try editor.validateState();
}

// No-op navigation/deletion must preserve a valid active selection at an edge.
// This matters when the engine repeats a held key across multiple frames.
test "stage28_68 boundary no-ops preserve selection and caller storage" {
    const t = std.testing;
    var storage: [16]u8 = @splat(0xa5);
    var editor = try Buffer.init(&storage, "a€🚀b");

    try editor.select(8, 0);
    const before_left = storage;
    try t.expect(!(try editor.moveLeftSelecting()));
    try t.expect(!(try editor.moveLeft()));
    try t.expectEqual(@as(usize, 0), editor.cursor);
    try t.expectEqual(@as(?usize, 8), editor.anchor);
    try t.expectEqualSlices(u8, &before_left, &storage);
    try editor.validateState();

    try editor.select(1, 9);
    const before_right = storage;
    try t.expect(!(try editor.moveRightSelecting()));
    try t.expect(!(try editor.moveRight()));
    try t.expectEqual(@as(usize, 9), editor.cursor);
    try t.expectEqual(@as(?usize, 1), editor.anchor);
    try t.expectEqualSlices(u8, &before_right, &storage);
    try editor.validateState();
}

test "stage28_68 boundary deletions with collapsed anchor are non-mutating" {
    const t = std.testing;
    var storage: [12]u8 = @splat(0xa5);
    var editor = try Buffer.init(&storage, "a€b");
    try editor.setCursor(0);
    editor.anchor = 0;
    const before = storage;
    try t.expect(!(try editor.backspace()));
    try t.expectEqual(@as(?usize, 0), editor.anchor);
    try t.expectEqual(@as(usize, 0), editor.cursor);
    try t.expectEqualSlices(u8, &before, &storage);
    try editor.validateState();

    try editor.setCursor(editor.len);
    editor.anchor = editor.len;
    try t.expect(!(try editor.deleteForward()));
    try t.expectEqual(@as(?usize, 5), editor.anchor);
    try t.expectEqual(@as(usize, 5), editor.cursor);
    try t.expectEqualSlices(u8, &before, &storage);
    try editor.validateState();
}
