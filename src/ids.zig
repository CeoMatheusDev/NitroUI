//! Deterministic hierarchical widget IDs, without heap allocations.
//! Hash algorithm: FNV-1a 64-bit over a tagged, length-delimited stream.
const std = @import("std");

pub const Id = u64;
pub const max_depth: usize = 64;
pub const Error = error{ ScopeOverflow, ScopeUnderflow, UnbalancedScopes };
const offset_basis: u64 = 0xcbf29ce484222325;
const prime: u64 = 0x100000001b3;

fn byte(hash: u64, value: u8) u64 {
    return (hash ^ @as(u64, value)) *% prime;
}

fn integer(hash: u64, value: u64) u64 {
    var h = hash;
    var v = value;
    for (0..8) |_| {
        h = byte(h, @truncate(v));
        v >>= 8;
    }
    return h;
}

fn segment(parent: Id, tag: u8, bytes: []const u8) Id {
    var h = byte(parent, tag);
    h = integer(h, @intCast(bytes.len));
    for (bytes) |b| h = byte(h, b);
    return h;
}

pub const Stack = struct {
    seeds: [max_depth + 1]Id = undefined,
    depth: usize = 0,

    pub fn init() Stack {
        var self: Stack = .{};
        self.seeds[0] = offset_basis;
        return self;
    }

    /// Begin a new frame with the root scope. Every frame must balance its scopes.
    pub fn reset(self: *Stack) void {
        self.depth = 0;
        self.seeds[0] = offset_basis;
    }

    pub fn current(self: *const Stack) Id {
        if (self.depth > max_depth) return offset_basis;
        return self.seeds[self.depth];
    }

    pub fn idString(self: *const Stack, label: []const u8) Id {
        return segment(self.current(), 1, label);
    }

    pub fn idInteger(self: *const Stack, value: u64) Id {
        return integer(byte(self.current(), 2), value);
    }

    pub fn pushString(self: *Stack, label: []const u8) Error!void {
        if (self.depth >= max_depth) return error.ScopeOverflow;
        const next = self.idString(label);
        self.depth += 1;
        self.seeds[self.depth] = next;
    }

    pub fn pushInteger(self: *Stack, value: u64) Error!void {
        if (self.depth >= max_depth) return error.ScopeOverflow;
        const next = self.idInteger(value);
        self.depth += 1;
        self.seeds[self.depth] = next;
    }

    pub fn pop(self: *Stack) Error!void {
        if (self.depth == 0) return error.ScopeUnderflow;
        self.depth -= 1;
    }

    pub fn validateBalanced(self: *const Stack) Error!void {
        if (self.depth != 0) return error.UnbalancedScopes;
    }
};

test "determinism, hierarchy, tags and length boundaries" {
    const testing = std.testing;
    var s = Stack.init();
    const root = s.idString("ok");
    try testing.expectEqual(root, s.idString("ok"));
    try testing.expect(root != s.idString("other"));
    try testing.expect(s.idString("1") != s.idInteger(1));
    try s.pushString("a");
    const a = s.idString("b");
    try s.pop();
    try s.pushString("ab");
    try testing.expect(a != s.idString(""));
    try s.pop();
    try testing.expectEqual(root, s.idString("ok"));
}

test "scope limits and recovery" {
    const testing = std.testing;
    var s = Stack.init();
    try testing.expectError(error.ScopeUnderflow, s.pop());
    for (0..max_depth) |i| try s.pushInteger(@intCast(i));
    const previous = s.current();
    try testing.expectError(error.ScopeOverflow, s.pushString("extra"));
    try testing.expectEqual(previous, s.current());
    try testing.expectError(error.UnbalancedScopes, s.validateBalanced());
    for (0..max_depth) |_| try s.pop();
    try s.validateBalanced();
    s.reset();
    try s.validateBalanced();
}

test "stage24_8 corrupted depth cannot cause out-of-bounds access" {
    const testing = std.testing;
    var s = Stack.init();
    s.depth = max_depth + 5;
    try testing.expectError(error.ScopeOverflow, s.pushString("x"));
    try testing.expectError(error.ScopeOverflow, s.pushInteger(1));
    try testing.expectEqual(offset_basis, s.current());
}
