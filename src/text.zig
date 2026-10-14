//! UTF-8 decoding and allocation-free text geometry emission.
const std = @import("std");
const draw = @import("draw.zig");
const font_mod = @import("font.zig");

pub const Error = error{ InvalidUtf8, MissingGlyph, InvalidScale, InvalidPosition };

pub const Metrics = struct {
    advance_x: f32,
    glyph_count: usize,
};

pub const Decoded = struct { codepoint: u21, len: usize };

/// Decode one UTF-8 scalar. Rejects overlong sequences, surrogates and values
/// above U+10FFFF. Empty input is not a scalar and returns InvalidUtf8.
pub fn decodeOne(bytes: []const u8) Error!Decoded {
    if (bytes.len == 0) return error.InvalidUtf8;
    const b0 = bytes[0];
    if (b0 < 0x80) return .{ .codepoint = b0, .len = 1 };
    var cp: u32 = 0;
    var need: usize = 0;
    var minimum: u32 = 0;
    if (b0 >= 0xC2 and b0 <= 0xDF) {
        cp = b0 & 0x1F;
        need = 2;
        minimum = 0x80;
    } else if (b0 >= 0xE0 and b0 <= 0xEF) {
        cp = b0 & 0x0F;
        need = 3;
        minimum = 0x800;
    } else if (b0 >= 0xF0 and b0 <= 0xF4) {
        cp = b0 & 0x07;
        need = 4;
        minimum = 0x10000;
    } else return error.InvalidUtf8;
    if (bytes.len < need) return error.InvalidUtf8;
    for (bytes[1..need]) |b| {
        if ((b & 0xC0) != 0x80) return error.InvalidUtf8;
        cp = (cp << 6) | (b & 0x3F);
    }
    if (cp < minimum or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF)) return error.InvalidUtf8;
    return .{ .codepoint = @intCast(cp), .len = need };
}

/// Measure one line of UTF-8 text. Newline handling is intentionally deferred
/// to layout; control bytes are resolved like any other codepoint.
pub fn measure(font: font_mod.Font, utf8: []const u8, scale: f32) (Error || font_mod.Error)!Metrics {
    if (!std.math.isFinite(scale) or scale <= 0) return error.InvalidScale;
    var offset: usize = 0;
    var advance: f32 = 0;
    var count: usize = 0;
    while (offset < utf8.len) {
        const decoded = try decodeOne(utf8[offset..]);
        const resolved_glyph = font.resolve(decoded.codepoint) orelse return error.MissingGlyph;
        const next = advance + resolved_glyph.advance_x * scale;
        if (!std.math.isFinite(next)) return error.InvalidScale;
        advance = next;
        count += 1;
        offset += decoded.len;
    }
    return .{ .advance_x = advance, .glyph_count = count };
}

/// Map a horizontal coordinate in text-local pixels to the nearest UTF-8
/// scalar boundary. Midpoints between consecutive pen positions determine
/// placement; ties choose the boundary on the right. No allocations.
pub fn caretOffsetAtX(font: font_mod.Font, utf8: []const u8, scale: f32, x: f32) (Error || font_mod.Error)!usize {
    if (!std.math.isFinite(x)) return error.InvalidPosition;
    if (!std.math.isFinite(scale) or scale <= 0) return error.InvalidScale;
    var offset: usize = 0;
    var pen: f32 = 0;
    while (offset < utf8.len) {
        const decoded = try decodeOne(utf8[offset..]);
        const resolved_glyph = font.resolve(decoded.codepoint) orelse return error.MissingGlyph;
        const advance = resolved_glyph.advance_x * scale;
        const next = pen + advance;
        if (!std.math.isFinite(next)) return error.InvalidScale;
        const midpoint = pen + advance * 0.5;
        if (!std.math.isFinite(midpoint)) return error.InvalidScale;
        if (x < midpoint) return offset;
        pen = next;
        offset += decoded.len;
    }
    return utf8.len;
}

/// Emit one line of text from a baseline origin. On any error, public geometry
/// counts and the previously mergeable command are restored, so no partial
/// string is visible through Buffer.view()/Context.drawDataView().
pub fn emitBaseline(buffer: *draw.Buffer, font: font_mod.Font, utf8: []const u8, baseline: [2]f32, scale: f32, color: u32, clip: draw.ClipRect) (Error || font_mod.Error || draw.Error)!Metrics {
    if (!std.math.isFinite(baseline[0]) or !std.math.isFinite(baseline[1])) return error.InvalidPosition;
    const metrics = try measure(font, utf8, scale);
    // Public buffer counters may have been corrupted by the caller.
    // Never read commands[old_c - 1] until its bounds are verified.
    if (buffer.vertex_count > buffer.vertices.len or
        buffer.index_count > buffer.indices.len or
        buffer.command_count > buffer.commands.len) return error.OutOfCapacity;
    const old_v = buffer.vertex_count;
    const old_i = buffer.index_count;
    const old_c = buffer.command_count;
    const old_last = if (old_c > 0) buffer.commands[old_c - 1] else null;
    errdefer {
        buffer.vertex_count = old_v;
        buffer.index_count = old_i;
        buffer.command_count = old_c;
        if (old_last) |command| buffer.commands[old_c - 1] = command;
    }

    var offset: usize = 0;
    var pen_x = baseline[0];
    while (offset < utf8.len) {
        const decoded = try decodeOne(utf8[offset..]);
        const resolved_glyph = font.resolve(decoded.codepoint) orelse return error.MissingGlyph;
        if (!std.math.isFinite(pen_x)) return error.InvalidPosition;
        const x0 = pen_x + resolved_glyph.bearing_x * scale;
        const y0 = baseline[1] - resolved_glyph.bearing_y * scale;
        const x1 = x0 + resolved_glyph.width * scale;
        const y1 = y0 + resolved_glyph.height * scale;
        if (!std.math.isFinite(x0) or !std.math.isFinite(y0) or !std.math.isFinite(x1) or !std.math.isFinite(y1)) return error.InvalidPosition;
        if (resolved_glyph.width > 0 and resolved_glyph.height > 0) {
            try buffer.addTexturedQuad(
                .{ .{ x0, y0 }, .{ x1, y0 }, .{ x1, y1 }, .{ x0, y1 } },
                .{ .{ resolved_glyph.u0, resolved_glyph.v0 }, .{ resolved_glyph.u1, resolved_glyph.v0 }, .{ resolved_glyph.u1, resolved_glyph.v1 }, .{ resolved_glyph.u0, resolved_glyph.v1 } },
                color,
                font.texture,
                clip,
            );
        }
        pen_x += resolved_glyph.advance_x * scale;
        if (!std.math.isFinite(pen_x)) return error.InvalidPosition;
        offset += decoded.len;
    }
    return metrics;
}

fn glyph(cp: u21, advance: f32, width: f32) font_mod.Glyph {
    return .{ .codepoint = cp, .advance_x = advance, .bearing_x = 1, .bearing_y = 7, .width = width, .height = 8, .u0 = 0.1, .v0 = 0.2, .u1 = 0.3, .v1 = 0.4 };
}

test "utf8 decoder accepts scalar boundaries and rejects malformed input" {
    const t = std.testing;
    try t.expectEqual(@as(u21, 'A'), (try decodeOne("A")).codepoint);
    try t.expectEqual(@as(u21, 0x20AC), (try decodeOne("€")).codepoint);
    try t.expectEqual(@as(u21, 0x1F600), (try decodeOne("😀")).codepoint);
    try t.expectError(error.InvalidUtf8, decodeOne(&.{ 0xC0, 0x80 }));
    try t.expectError(error.InvalidUtf8, decodeOne(&.{ 0xED, 0xA0, 0x80 }));
    try t.expectError(error.InvalidUtf8, decodeOne(&.{ 0xF4, 0x90, 0x80, 0x80 }));
}

test "text measure resolves fallback without allocations" {
    const glyphs = [_]font_mod.Glyph{ glyph(63, 5, 4), glyph(65, 7, 6) };
    const font: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1, .fallback = 63 };
    try font.validate();
    const m = try measure(font, "AB", 2);
    try std.testing.expectEqual(@as(usize, 2), m.glyph_count);
    try std.testing.expectEqual(@as(f32, 24), m.advance_x);
}

test "text emission writes UV geometry and batches glyphs" {
    const glyphs = [_]font_mod.Glyph{glyph(65, 7, 6)};
    const font: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    var vertices: [8]draw.Vertex = undefined;
    var indices: [12]u32 = undefined;
    var commands: [2]draw.Command = undefined;
    var buffer = draw.Buffer.init(&vertices, &indices, &commands);
    const clip: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    _ = try emitBaseline(&buffer, font, "AA", .{ 10, 20 }, 1, 0xffffffff, clip);
    try std.testing.expectEqual(@as(usize, 8), buffer.vertex_count);
    try std.testing.expectEqual(@as(usize, 12), buffer.index_count);
    try std.testing.expectEqual(@as(usize, 1), buffer.command_count);
    try std.testing.expectEqual(@as(f32, 0.1), buffer.vertices[0].u);
    try std.testing.expectEqual(@as(f32, 0.4), buffer.vertices[2].v);
}

test "text emission rolls back visible geometry on capacity failure" {
    const glyphs = [_]font_mod.Glyph{glyph(65, 7, 6)};
    const font: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    var vertices: [4]draw.Vertex = undefined;
    var indices: [6]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    var buffer = draw.Buffer.init(&vertices, &indices, &commands);
    const clip: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try std.testing.expectError(error.OutOfCapacity, emitBaseline(&buffer, font, "AA", .{ 0, 10 }, 1, 0xffffffff, clip));
    try std.testing.expectEqual(@as(usize, 0), buffer.vertex_count);
    try std.testing.expectEqual(@as(usize, 0), buffer.index_count);
    try std.testing.expectEqual(@as(usize, 0), buffer.command_count);
}

test "utf8 decoder covers boundaries, invalid continuations and truncation" {
    const t = std.testing;
    try t.expectEqual(@as(u21, 0x7f), (try decodeOne(&.{0x7f})).codepoint);
    try t.expectEqual(@as(u21, 0x80), (try decodeOne(&.{ 0xc2, 0x80 })).codepoint);
    try t.expectEqual(@as(u21, 0x7ff), (try decodeOne(&.{ 0xdf, 0xbf })).codepoint);
    try t.expectEqual(@as(u21, 0x800), (try decodeOne(&.{ 0xe0, 0xa0, 0x80 })).codepoint);
    try t.expectEqual(@as(u21, 0xffff), (try decodeOne(&.{ 0xef, 0xbf, 0xbf })).codepoint);
    try t.expectEqual(@as(u21, 0x10000), (try decodeOne(&.{ 0xf0, 0x90, 0x80, 0x80 })).codepoint);
    try t.expectEqual(@as(u21, 0x10ffff), (try decodeOne(&.{ 0xf4, 0x8f, 0xbf, 0xbf })).codepoint);
    const malformed = [_][]const u8{
        &.{},                         &.{0x80},               &.{0xc2},                     &.{ 0xe2, 0x82 },       &.{ 0xf0, 0x90, 0x80 },
        &.{ 0xc2, 0x41 },             &.{ 0xe2, 0x28, 0xa1 }, &.{ 0xf0, 0x90, 0x41, 0x80 }, &.{ 0xe0, 0x9f, 0xbf }, &.{ 0xf0, 0x8f, 0xbf, 0xbf },
        &.{ 0xf5, 0x80, 0x80, 0x80 }, &.{0xff},
    };
    for (malformed) |bytes| try t.expectError(error.InvalidUtf8, decodeOne(bytes));
}

test "empty text emits nothing and invalid input preserves geometry" {
    const t = std.testing;
    var glyphs = [_]font_mod.Glyph{glyph(65, 7, 6)};
    glyphs[0].bearing_x = 3.0e38;
    const f: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    var vertices: [8]draw.Vertex = undefined;
    var indices: [12]u32 = undefined;
    var commands: [2]draw.Command = undefined;
    var buffer = draw.Buffer.init(&vertices, &indices, &commands);
    const clip: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    const empty = try emitBaseline(&buffer, f, "", .{ 0, 10 }, 1, 0xffffffff, clip);
    try t.expectEqual(@as(usize, 0), empty.glyph_count);
    try t.expectEqual(@as(usize, 0), buffer.command_count);
    _ = try emitBaseline(&buffer, f, "A", .{ 0, 10 }, 1, 0xffffffff, clip);
    const original = buffer.commands[0];
    try t.expectError(error.InvalidUtf8, emitBaseline(&buffer, f, &.{ 0xc0, 0x80 }, .{ 0, 10 }, 1, 0xffffffff, clip));
    try t.expectError(error.MissingGlyph, emitBaseline(&buffer, f, "B", .{ 0, 10 }, 1, 0xffffffff, clip));
    try t.expectEqual(@as(usize, 4), buffer.vertex_count);
    try t.expectEqual(@as(usize, 6), buffer.index_count);
    try t.expectEqual(@as(usize, 1), buffer.command_count);
    try t.expectEqualDeep(original, buffer.commands[0]);
}

test "text rollback restores existing batched command on overflow" {
    const t = std.testing;
    var glyphs = [_]font_mod.Glyph{glyph(65, 7, 6)};
    glyphs[0].bearing_x = 3.0e38;
    const f: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    var vertices: [8]draw.Vertex = undefined;
    var indices: [12]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    var buffer = draw.Buffer.init(&vertices, &indices, &commands);
    const clip: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    _ = try emitBaseline(&buffer, f, "A", .{ 0, 10 }, 1, 0xffffffff, clip);
    const original = buffer.commands[0];
    try t.expectError(error.OutOfCapacity, emitBaseline(&buffer, f, "AA", .{ 0, 10 }, 1, 0xffffffff, clip));
    try t.expectEqual(@as(usize, 4), buffer.vertex_count);
    try t.expectEqual(@as(usize, 6), buffer.index_count);
    try t.expectEqual(@as(usize, 1), buffer.command_count);
    try t.expectEqualDeep(original, buffer.commands[0]);
}

test "text rejects corrupt public command count without indexing out of bounds" {
    const t = std.testing;
    const glyphs = [_]font_mod.Glyph{glyph(65, 7, 6)};
    const f: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    var vertices: [4]draw.Vertex = undefined;
    var indices: [6]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    var buffer = draw.Buffer.init(&vertices, &indices, &commands);
    buffer.command_count = 2;
    const clip: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try t.expectError(error.OutOfCapacity, emitBaseline(&buffer, f, "A", .{ 0, 10 }, 1, 0xffffffff, clip));
    try t.expectEqual(@as(usize, 2), buffer.command_count);
}

test "text rejects nonfinite glyph placement and baseline accumulation" {
    const t = std.testing;
    var glyphs = [_]font_mod.Glyph{glyph(65, 7, 6)};
    glyphs[0].bearing_x = 3.0e38;
    const f: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    var vertices: [8]draw.Vertex = undefined;
    var indices: [12]u32 = undefined;
    var commands: [2]draw.Command = undefined;
    var buffer = draw.Buffer.init(&vertices, &indices, &commands);
    const clip: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try t.expectError(error.InvalidPosition, emitBaseline(&buffer, f, "AA", .{ 3.0e38, 10 }, 1, 0xffffffff, clip));
    try t.expectEqual(@as(usize, 0), buffer.vertex_count);
    try t.expectEqual(@as(usize, 0), buffer.command_count);
}

test "caret hit testing uses variable glyph advances and UTF-8 boundaries" {
    const t = std.testing;
    const glyphs = [_]font_mod.Glyph{
        glyph(65, 4, 4),
        glyph(66, 12, 10),
        glyph(0x00e9, 8, 7),
    };
    const f: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    const content = "ABé";
    try t.expectEqual(@as(usize, 0), try caretOffsetAtX(f, content, 1, -100));
    try t.expectEqual(@as(usize, 1), try caretOffsetAtX(f, content, 1, 2));
    try t.expectEqual(@as(usize, 1), try caretOffsetAtX(f, content, 1, 9));
    try t.expectEqual(@as(usize, 2), try caretOffsetAtX(f, content, 1, 10));
    try t.expectEqual(@as(usize, 4), try caretOffsetAtX(f, content, 1, 20));
    try t.expectError(error.InvalidPosition, caretOffsetAtX(f, content, 1, std.math.nan(f32)));
}

// Every possible leading byte is classified independently of the decoder.
// This catches accidental acceptance of continuation bytes, overlong leads,
// and values beyond the four-byte UTF-8 encoding range.
test "stage28_70 exhaustive UTF-8 leading-byte classification" {
    const t = std.testing;
    var lead: usize = 0;
    while (lead < 256) : (lead += 1) {
        const b: u8 = @intCast(lead);
        const sample = [_]u8{ b, 0x80, 0x80, 0x80 };
        if (lead < 0x80) {
            const decoded = try decodeOne(sample[0..]);
            try t.expectEqual(@as(usize, 1), decoded.len);
            try t.expectEqual(@as(u21, b), decoded.codepoint);
        } else {
            // A single leading byte can never encode a non-ASCII scalar.
            try t.expectError(error.InvalidUtf8, decodeOne(sample[0..1]));
            // A continuation-byte suffix of all 0x80 is only valid for
            // 0xC2..0xDF, 0xE1..0xEF and 0xF1..0xF4. E0/F0
            // with a 0x80 second byte would be overlong.
            const valid_two = lead >= 0xc2 and lead <= 0xdf;
            const valid_three = lead >= 0xe1 and lead <= 0xef;
            const valid_four = lead >= 0xf1 and lead <= 0xf4;
            const expected_len: usize = if (valid_two) 2 else if (valid_three) 3 else if (valid_four) 4 else 0;
            if (expected_len == 0) {
                try t.expectError(error.InvalidUtf8, decodeOne(sample[0..]));
            } else {
                const decoded = try decodeOne(sample[0..]);
                try t.expectEqual(expected_len, decoded.len);
            }
        }
    }
}
