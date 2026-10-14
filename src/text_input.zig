//! Ordered, backend-independent keyboard/text bridge for a focused UTF-8 editor.
//! Caller must supply the complete ordered event stream; Processor.events only
//! contains its latest batch. No allocations, clipboard, IME, or OS access.
const std = @import("std");
const input = @import("input.zig");
const edit = @import("text_edit.zig");

pub const Keys = struct {
    // Reserved logical codes; the engine translates platform key codes.
    pub const backspace: input.Key = 8;
    pub const delete: input.Key = 127;
    pub const left: input.Key = 37;
    pub const right: input.Key = 39;
    pub const home: input.Key = 36;
    pub const end: input.Key = 35;
};

/// Events must be valid according to input.Processor.process. `initial_shift`
/// is the modifier state immediately before the first event (not the final
/// frame snapshot). On an edit error earlier events may already be applied;
/// the failing scalar insertion itself remains atomic.
/// Use `applyTracked` to recover the consumed prefix after an error.
pub const Progress = struct {
    /// Number of fully processed events, including ignored events.
    consumed: usize = 0,
    /// Number of successful text-changing operations.
    changes: usize = 0,
    /// Modifier and focus states after the consumed prefix.
    shift: bool = false,
    focused: bool = false,
};

/// Reports the successfully consumed prefix even when an edit fails.
/// On failure, events[progress.consumed] was NOT consumed; do not replay
/// events before that index. The failed edit is atomic.
/// The caller must retain this progress if processing multiple event batches.
pub fn applyTracked(editor: *edit.Buffer, events: []const input.Event, initial_shift: bool, initially_focused: bool, progress: *Progress) edit.Error!void {
    progress.* = .{ .shift = initial_shift, .focused = initially_focused };
    var shift = initial_shift;
    var focused = initially_focused;
    var changes: usize = 0;
    for (events) |event| {
        // `errdefer` runs on failure, but only successful
        // events advance `consumed`; errors leave the failing index intact.
        errdefer {
            progress.changes = changes;
            progress.shift = shift;
            progress.focused = focused;
        }
        switch (event) {
            .focus => |value| {
                focused = value;
                if (!value) shift = false;
            },
            .key => |key| {
                if (key.code == input.NavigationKey.shift) {
                    shift = focused and key.down;
                } else if (focused and key.down) switch (key.code) {
                    Keys.left => {
                        if (shift) {
                            _ = try editor.moveLeftSelecting();
                        } else {
                            _ = try editor.moveLeft();
                        }
                    },
                    Keys.right => {
                        if (shift) {
                            _ = try editor.moveRightSelecting();
                        } else {
                            _ = try editor.moveRight();
                        }
                    },
                    Keys.home, Keys.end => {
                        const target: usize = if (key.code == Keys.home) 0 else editor.len;
                        if (shift) {
                            try editor.select(editor.anchor orelse editor.cursor, target);
                        } else {
                            try editor.setCursor(target);
                        }
                    },
                    Keys.backspace => {
                        if (try editor.backspace()) changes += 1;
                    },
                    Keys.delete => {
                        if (try editor.deleteForward()) changes += 1;
                    },
                    else => {},
                };
            },
            .text => |scalar| {
                if (focused) {
                    try editor.replaceSelectionScalar(scalar);
                    changes += 1;
                }
            },
            else => {},
        }
        progress.consumed += 1;
        progress.changes = changes;
        progress.shift = shift;
        progress.focused = focused;
    }
}

/// Compatibility wrapper; use applyTracked for error recovery.
pub fn apply(editor: *edit.Buffer, events: []const input.Event, initial_shift: bool, initially_focused: bool) edit.Error!usize {
    var progress: Progress = .{};
    try applyTracked(editor, events, initial_shift, initially_focused, &progress);
    return progress.changes;
}

test "ordered Unicode insertion and selection replacement" {
    const t = std.testing;
    var storage: [32]u8 = undefined;
    var editor = try edit.Buffer.init(&storage, "ab");
    const changes = try apply(&editor, &.{
        .{ .key = .{ .code = Keys.left, .down = true } },
        .{ .key = .{ .code = input.NavigationKey.shift, .down = true } },
        .{ .key = .{ .code = Keys.left, .down = true } },
        .{ .text = 0x20ac },
        .{ .key = .{ .code = input.NavigationKey.shift, .down = false } },
    }, false, true);
    try t.expectEqual(@as(usize, 1), changes);
    try t.expectEqualStrings("€b", editor.view());
    try t.expect(editor.selection() == null);
}

test "focus loss ignores subsequent edits and home end selection" {
    const t = std.testing;
    var storage: [32]u8 = undefined;
    var editor = try edit.Buffer.init(&storage, "abc");
    const changes = try apply(&editor, &.{
        .{ .key = .{ .code = Keys.home, .down = true } },
        .{ .key = .{ .code = input.NavigationKey.shift, .down = true } },
        .{ .key = .{ .code = Keys.end, .down = true } },
        .{ .focus = false },
        .{ .text = 'X' },
        .{ .key = .{ .code = Keys.backspace, .down = true } },
    }, false, true);
    try t.expectEqual(@as(usize, 0), changes);
    try t.expectEqualStrings("abc", editor.view());
    try t.expectEqual(@as(usize, 3), editor.selection().?.end);
}

test "capacity failure preserves failing edit and prior events" {
    const t = std.testing;
    var storage: [3]u8 = undefined;
    var editor = try edit.Buffer.init(&storage, "ab");
    try t.expectError(error.OutOfCapacity, apply(&editor, &.{
        .{ .text = 'c' },
        .{ .text = 0x1f600 },
    }, false, true));
    try t.expectEqualStrings("abc", editor.view());
    try t.expectEqual(@as(usize, 3), editor.cursor);
}

test "tracked failure reports exact consumed prefix and allows resumption" {
    const t = std.testing;
    var storage: [4]u8 = undefined;
    var editor = try edit.Buffer.init(&storage, "ab");
    const events = [_]input.Event{
        .{ .text = 'c' },
        .{ .text = 0x1f600 },
        .{ .key = .{ .code = Keys.left, .down = true } },
    };
    var progress: Progress = .{};
    try t.expectError(error.OutOfCapacity, applyTracked(&editor, &events, false, true, &progress));
    try t.expectEqual(@as(usize, 1), progress.consumed);
    try t.expectEqual(@as(usize, 1), progress.changes);
    try t.expectEqualStrings("abc", editor.view());
    // Skip the failed event and continue with the remaining suffix.
    var tail: Progress = .{};
    try applyTracked(&editor, events[2..], progress.shift, progress.focused, &tail);
    try t.expectEqual(@as(usize, 1), tail.consumed);
    try t.expectEqual(@as(usize, 2), editor.cursor);
}

test "focus loss resets shift and ignored events count as consumed" {
    const t = std.testing;
    var storage: [16]u8 = undefined;
    var editor = try edit.Buffer.init(&storage, "ab");
    var progress: Progress = .{};
    try applyTracked(&editor, &.{
        .{ .key = .{ .code = input.NavigationKey.shift, .down = true } },
        .{ .focus = false },
        .{ .key = .{ .code = Keys.left, .down = true } },
        .{ .focus = true },
        .{ .key = .{ .code = Keys.left, .down = true, .repeat = true } },
    }, false, true, &progress);
    try t.expectEqual(@as(usize, 5), progress.consumed);
    try t.expectEqual(@as(usize, 0), progress.changes);
    try t.expect(!progress.shift);
    try t.expect(progress.focused);
    try t.expectEqual(@as(usize, 1), editor.cursor);
    try t.expect(editor.selection() == null);
}

test "stage28_28 tracked failure retains modifier state and consumed prefix" {
    const t = std.testing;
    var storage: [3]u8 = undefined;
    var editor = try edit.Buffer.init(&storage, "ab");
    const events = [_]input.Event{
        .{ .key = .{ .code = input.NavigationKey.shift, .down = true } },
        .{ .key = .{ .code = Keys.left, .down = true } },
        .{ .text = 0x1f600 }, // Four UTF-8 bytes cannot fit in the buffer.
        .{ .key = .{ .code = input.NavigationKey.shift, .down = false } },
        .{ .key = .{ .code = Keys.right, .down = true } },
    };
    var progress: Progress = .{ .consumed = 99, .changes = 99 };
    try t.expectError(error.OutOfCapacity, applyTracked(&editor, &events, false, true, &progress));
    try t.expectEqual(@as(usize, 2), progress.consumed);
    try t.expectEqual(@as(usize, 0), progress.changes);
    try t.expect(progress.shift);
    try t.expect(progress.focused);
    try t.expectEqualStrings("ab", editor.view());
    try t.expectEqual(@as(usize, 1), editor.cursor);
    try t.expect(editor.selection() != null);

    // The engine explicitly discards the failed insertion, then processes
    // only the unconsumed suffix using the reported modifier/focus state.
    var resumed: Progress = .{};
    try applyTracked(&editor, events[3..], progress.shift, progress.focused, &resumed);
    try t.expectEqual(@as(usize, 2), resumed.consumed);
    try t.expectEqual(@as(usize, 0), resumed.changes);
    try t.expect(!resumed.shift);
    try t.expect(resumed.focused);
    try t.expectEqual(@as(usize, 2), editor.cursor);
    try t.expect(editor.selection() == null);
    try t.expectEqualStrings("ab", editor.view());
}

test "stage28_29 failed Unicode replacement preserves selection and progress" {
    const t = std.testing;
    var storage: [3]u8 = undefined;
    var editor = try edit.Buffer.init(&storage, "abc");
    try editor.select(1, 3);
    const events = [_]input.Event{
        .{ .key = .{ .code = input.NavigationKey.shift, .down = true } },
        .{ .text = 0x1f680 }, // Four-byte scalar exceeds total capacity.
        .{ .key = .{ .code = input.NavigationKey.shift, .down = false } },
        .{ .key = .{ .code = Keys.left, .down = true } },
    };
    var progress: Progress = .{ .consumed = 100, .changes = 100 };
    try t.expectError(error.OutOfCapacity, applyTracked(&editor, &events, false, true, &progress));
    try t.expectEqual(@as(usize, 1), progress.consumed);
    try t.expectEqual(@as(usize, 0), progress.changes);
    try t.expect(progress.shift);
    try t.expect(progress.focused);
    try t.expectEqualStrings("abc", editor.view());
    try t.expectEqual(@as(usize, 3), editor.len);
    try t.expectEqual(@as(usize, 3), editor.cursor);
    const selection = editor.selection().?;
    try t.expectEqual(@as(usize, 1), selection.start);
    try t.expectEqual(@as(usize, 3), selection.end);

    // The engine explicitly drops the failed scalar, retaining only the tail.
    var resumed: Progress = .{};
    try applyTracked(&editor, events[2..], progress.shift, progress.focused, &resumed);
    try t.expectEqual(@as(usize, 2), resumed.consumed);
    try t.expectEqual(@as(usize, 0), resumed.changes);
    try t.expect(!resumed.shift);
    try t.expectEqual(@as(usize, 2), editor.cursor);
    try t.expect(editor.selection() == null);
    try t.expectEqualStrings("abc", editor.view());
}

test "stage28_29 invalid scalar is atomic after consumed prefix" {
    const t = std.testing;
    var storage: [8]u8 = undefined;
    var editor = try edit.Buffer.init(&storage, "ab");
    const events = [_]input.Event{
        .{ .key = .{ .code = Keys.left, .down = true } },
        .{ .text = 0xd800 }, // Surrogate is not a Unicode scalar value.
        .{ .text = 'Z' },
    };
    var progress: Progress = .{};
    try t.expectError(error.InvalidScalar, applyTracked(&editor, &events, false, true, &progress));
    try t.expectEqual(@as(usize, 1), progress.consumed);
    try t.expectEqual(@as(usize, 0), progress.changes);
    try t.expectEqualStrings("ab", editor.view());
    try t.expectEqual(@as(usize, 1), editor.cursor);
    var resumed: Progress = .{};
    try applyTracked(&editor, events[2..], progress.shift, progress.focused, &resumed);
    try t.expectEqual(@as(usize, 1), resumed.consumed);
    try t.expectEqual(@as(usize, 1), resumed.changes);
    try t.expectEqualStrings("aZb", editor.view());
}

test "stage28_30 focus loss clears Shift before a failing insertion" {
    const t = std.testing;
    var storage: [2]u8 = undefined;
    var editor = try edit.Buffer.init(&storage, "ab");
    const events = [_]input.Event{
        .{ .key = .{ .code = input.NavigationKey.shift, .down = true } },
        .{ .focus = false },
        .{ .focus = true },
        .{ .text = 'X' }, // No room; failure must preserve preceding focus transitions.
        .{ .key = .{ .code = Keys.left, .down = true } },
    };
    var progress: Progress = .{ .consumed = 99, .changes = 99, .shift = true };
    try t.expectError(error.OutOfCapacity, applyTracked(&editor, &events, false, true, &progress));
    try t.expectEqual(@as(usize, 3), progress.consumed);
    try t.expectEqual(@as(usize, 0), progress.changes);
    try t.expect(!progress.shift);
    try t.expect(progress.focused);
    try t.expectEqualStrings("ab", editor.view());
    try t.expectEqual(@as(usize, 2), editor.cursor);
    try t.expect(editor.selection() == null);

    // Engine drops the failed insertion and resumes from the unconsumed tail.
    var resumed: Progress = .{};
    try applyTracked(&editor, events[4..], progress.shift, progress.focused, &resumed);
    try t.expectEqual(@as(usize, 1), resumed.consumed);
    try t.expectEqual(@as(usize, 0), resumed.changes);
    try t.expectEqual(@as(usize, 1), editor.cursor);
    try t.expect(editor.selection() == null);
}

test "stage28_30 ignored events count as consumed and reset stale progress" {
    const t = std.testing;
    var storage: [4]u8 = undefined;
    var editor = try edit.Buffer.init(&storage, "a");
    var progress: Progress = .{ .consumed = 20, .changes = 10, .shift = true, .focused = true };
    try applyTracked(&editor, &.{
        .{ .focus = false },
        .{ .text = 'X' }, // Ignored while unfocused, but consumed.
        .{ .key = .{ .code = Keys.backspace, .down = true } },
    }, true, true, &progress);
    try t.expectEqual(@as(usize, 3), progress.consumed);
    try t.expectEqual(@as(usize, 0), progress.changes);
    try t.expect(!progress.shift);
    try t.expect(!progress.focused);
    try t.expectEqualStrings("a", editor.view());

    // Empty batches must also overwrite stale progress deterministically.
    try applyTracked(&editor, &.{}, false, false, &progress);
    try t.expectEqual(@as(usize, 0), progress.consumed);
    try t.expectEqual(@as(usize, 0), progress.changes);
    try t.expect(!progress.shift);
    try t.expect(!progress.focused);
}

test "stage28_31 successful selection replacement survives later capacity failure" {
    const t = std.testing;
    var storage: [4]u8 = undefined;
    var editor = try edit.Buffer.init(&storage, "abc");
    const events = [_]input.Event{
        .{ .key = .{ .code = input.NavigationKey.shift, .down = true } },
        .{ .key = .{ .code = Keys.left, .down = true } },
        .{ .text = 'X' }, // Replaces selected 'c' without increasing length.
        .{ .text = 0x1f680 }, // Four UTF-8 bytes cannot fit after "abX".
        .{ .key = .{ .code = Keys.left, .down = true } },
    };
    var progress: Progress = .{};
    try t.expectError(error.OutOfCapacity, applyTracked(&editor, &events, false, true, &progress));
    try t.expectEqual(@as(usize, 3), progress.consumed);
    try t.expectEqual(@as(usize, 1), progress.changes);
    try t.expect(progress.shift);
    try t.expect(progress.focused);
    try t.expectEqualStrings("abX", editor.view());
    try t.expectEqual(@as(usize, 3), editor.cursor);
    try t.expect(editor.selection() == null);

    // The host discards the failing insertion and resumes the remaining key.
    var resumed: Progress = .{};
    try applyTracked(&editor, events[4..], progress.shift, progress.focused, &resumed);
    try t.expectEqual(@as(usize, 1), resumed.consumed);
    try t.expectEqual(@as(usize, 0), resumed.changes);
    try t.expectEqualStrings("abX", editor.view());
    try t.expectEqual(@as(usize, 2), editor.cursor);
    const selection = editor.selection().?;
    try t.expectEqual(@as(usize, 2), selection.start);
    try t.expectEqual(@as(usize, 3), selection.end);
}

test "stage28_34 invalid editor cursor stops at failing navigation event" {
    const t = std.testing;
    var storage: [8]u8 = undefined;
    var editor = try edit.Buffer.init(&storage, "abc");
    // Simulate a caller violating the editor's public cursor invariant.
    editor.cursor = 9;
    const events = [_]input.Event{
        .{ .focus = true },
        .{ .key = .{ .code = Keys.left, .down = true } },
        .{ .text = 'Z' },
    };
    var progress: Progress = .{ .consumed = 42, .changes = 42 };
    try t.expectError(error.InvalidCursor, applyTracked(&editor, &events, false, true, &progress));
    try t.expectEqual(@as(usize, 1), progress.consumed);
    try t.expectEqual(@as(usize, 0), progress.changes);
    try t.expect(progress.focused);
    try t.expect(!progress.shift);
    try t.expectEqual(@as(usize, 9), editor.cursor);
    try t.expectEqualStrings("abc", editor.view());
}

test "stage28_35 invalid selection anchor stops navigation without consuming failing event" {
    const t = std.testing;
    var storage: [8]u8 = undefined;
    var editor = try edit.Buffer.init(&storage, "abc");
    editor.anchor = 9; // Simulate caller corruption of externally owned editor state.

    var progress: Progress = .{ .consumed = 99, .changes = 99, .shift = false, .focused = false };
    const events = [_]input.Event{
        .{ .key = .{ .code = input.NavigationKey.shift, .down = true } },
        .{ .key = .{ .code = Keys.home, .down = true } },
        .{ .text = 'Z' },
    };

    try t.expectError(error.InvalidCursor, applyTracked(&editor, &events, false, true, &progress));
    try t.expectEqual(@as(usize, 1), progress.consumed);
    try t.expectEqual(@as(usize, 0), progress.changes);
    try t.expect(progress.shift);
    try t.expect(progress.focused);
    try t.expectEqualStrings("abc", editor.view());
    try t.expectEqual(@as(usize, 3), editor.cursor);
    try t.expectEqual(@as(?usize, 9), editor.anchor);
}

test "stage28_37 caller repairs invalid cursor and replays only unconsumed suffix" {
    const t = std.testing;
    var storage: [12]u8 = undefined;
    var editor = try edit.Buffer.init(&storage, "abc");
    editor.cursor = 9; // Deliberate caller-side invariant violation.

    const events = [_]input.Event{
        .{ .focus = true },
        .{ .key = .{ .code = Keys.left, .down = true } },
        .{ .text = 'Z' },
    };
    var failed: Progress = .{};
    try t.expectError(error.InvalidCursor, applyTracked(&editor, &events, false, true, &failed));
    try t.expectEqual(@as(usize, 1), failed.consumed);
    try t.expectEqual(@as(usize, 0), failed.changes);
    try t.expectEqualStrings("abc", editor.view());

    // The application repairs its own corrupted state before retrying.
    editor.cursor = editor.len;
    try editor.validateState();
    var resumed: Progress = .{};
    try applyTracked(&editor, events[failed.consumed..], failed.shift, failed.focused, &resumed);
    try t.expectEqual(@as(usize, 2), resumed.consumed);
    try t.expectEqual(@as(usize, 1), resumed.changes);
    try t.expectEqualStrings("abZc", editor.view());
    try t.expectEqual(@as(usize, 3), editor.cursor);
    try t.expect(editor.selection() == null);
    try editor.validateState();
}

test "stage28_56 corrupted caller storage preserves event prefix and resumes after repair" {
    const t = std.testing;
    var storage = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
    var editor = try edit.Buffer.init(&storage, "a€b");
    storage[2] = 'X'; // The caller violates the UTF-8 storage contract.
    const damaged = storage;
    const events = [_]input.Event{
        .{ .key = .{ .code = input.NavigationKey.shift, .down = true } },
        .{ .key = .{ .code = Keys.left, .down = true } },
        .{ .key = .{ .code = input.NavigationKey.shift, .down = false } },
        .{ .text = 'Z' },
    };
    var progress: Progress = .{};
    try t.expectError(error.InvalidUtf8, applyTracked(&editor, &events, false, true, &progress));
    try t.expectEqual(@as(usize, 1), progress.consumed);
    try t.expectEqual(@as(usize, 0), progress.changes);
    try t.expect(progress.shift);
    try t.expect(progress.focused);
    try t.expectEqualSlices(u8, &damaged, &storage);
    try t.expectEqual(@as(usize, 5), editor.cursor);
    try t.expect(editor.anchor == null);

    // Caller repairs its storage and resumes only the unconsumed suffix.
    storage[2] = 0x82;
    try editor.validateState();
    var resumed: Progress = .{};
    try applyTracked(&editor, events[progress.consumed..], progress.shift, progress.focused, &resumed);
    try t.expectEqual(@as(usize, 3), resumed.consumed);
    try t.expectEqual(@as(usize, 1), resumed.changes);
    try t.expect(!resumed.shift);
    try t.expect(resumed.focused);
    try t.expectEqualStrings("a€Z", editor.view());
    try t.expect(editor.selection() == null);
    try editor.validateState();
}

test "stage28_69 invalid scalar event preserves prefix and resumes with selection" {
    const t = std.testing;
    var storage: [16]u8 = undefined;
    var editor = try edit.Buffer.init(&storage, "a€b");
    const events = [_]input.Event{
        .{ .key = .{ .code = input.NavigationKey.shift, .down = true } },
        .{ .key = .{ .code = Keys.left, .down = true } },
        .{ .text = 0xd800 }, // Invalid surrogate: must not consume the event.
        .{ .key = .{ .code = input.NavigationKey.shift, .down = false } },
        .{ .text = 'Z' },
    };
    var progress: Progress = .{};
    try t.expectError(error.InvalidScalar, applyTracked(&editor, &events, false, true, &progress));
    try t.expectEqual(@as(usize, 2), progress.consumed);
    try t.expectEqual(@as(usize, 0), progress.changes);
    try t.expect(progress.shift);
    try t.expect(progress.focused);
    try t.expectEqualStrings("a€b", editor.view());
    try t.expectEqual(@as(usize, 4), editor.cursor);
    try t.expectEqual(@as(usize, 5), editor.anchor.?);
    try editor.validateState();

    // Engine explicitly discards the failed scalar, not the successful prefix.
    var resumed: Progress = .{};
    try applyTracked(&editor, events[progress.consumed + 1 ..], progress.shift, progress.focused, &resumed);
    try t.expectEqual(@as(usize, 2), resumed.consumed);
    try t.expectEqual(@as(usize, 1), resumed.changes);
    try t.expect(!resumed.shift);
    try t.expect(resumed.focused);
    try t.expectEqualStrings("a€Z", editor.view());
    try t.expectEqual(@as(usize, 5), editor.cursor);
    try t.expect(editor.selection() == null);
    try editor.validateState();
}
