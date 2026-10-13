//! UTF-8 decoding and allocation-free text geometry emission.
const std = @import("std");
const draw = @import("draw.zig");
const font_mod = @import("font.zig");
const layout_mod = @import("layout.zig");

pub const Error = error{ InvalidUtf8, MissingGlyph, InvalidScale, InvalidPosition };

pub const Metrics = struct {
    advance_x: f32,
    glyph_count: usize,
};

/// Measured one-line box: horizontal advance plus scaled line height.
pub const LineBox = struct {
    width: f32,
    height: f32,
    glyph_count: usize,
};

const Decoded = struct { codepoint: u21, len: usize };

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
        const resolved = font.resolve(decoded.codepoint) orelse return error.MissingGlyph;
        const next = advance + resolved.advance_x * scale;
        if (!std.math.isFinite(next)) return error.InvalidScale;
        advance = next;
        count += 1;
        offset += decoded.len;
    }
    return .{ .advance_x = advance, .glyph_count = count };
}

/// Scaled line height: (ascent - descent + line_gap) * scale.
/// Revalidates font line metrics so unvalidated fonts fail explicitly
/// instead of producing non-finite geometry downstream.
pub fn lineHeight(font: font_mod.Font, scale: f32) (Error || font_mod.Error)!f32 {
    if (!std.math.isFinite(scale) or scale <= 0) return error.InvalidScale;
    if (!std.math.isFinite(font.ascent) or !std.math.isFinite(font.descent) or !std.math.isFinite(font.line_gap)) return error.InvalidFont;
    if (font.ascent < 0 or font.descent > 0 or font.line_gap < 0) return error.InvalidFont;
    const raw = font.ascent - font.descent + font.line_gap;
    if (!std.math.isFinite(raw) or raw <= 0) return error.InvalidFont;
    const scaled = raw * scale;
    if (!std.math.isFinite(scaled)) return error.InvalidScale;
    return scaled;
}

/// Combined one-line measurement for layout: width from `measure` and
/// height from `lineHeight`. Single traversal for width plus O(1) height.
pub fn lineBox(font: font_mod.Font, utf8: []const u8, scale: f32) (Error || font_mod.Error)!LineBox {
    const height = try lineHeight(font, scale);
    const m = try measure(font, utf8, scale);
    return .{ .width = m.advance_x, .height = height, .glyph_count = m.glyph_count };
}

/// Baseline origin for a layout row: left edge plus ascent offset.
/// `rect` is expected to come from `layout.Stack.next` sized with
/// `lineHeight`/`lineBox`; horizontal padding is already baked into `rect.x`.
/// Overflow or non-finite inputs return InvalidPosition without touching geometry.
pub fn baselineInRect(rect: layout_mod.Rect, font: font_mod.Font, scale: f32) (Error || font_mod.Error)![2]f32 {
    if (!std.math.isFinite(rect.x) or !std.math.isFinite(rect.y) or !std.math.isFinite(rect.width) or !std.math.isFinite(rect.height)) return error.InvalidPosition;
    if (rect.width < 0 or rect.height < 0) return error.InvalidPosition;
    if (!std.math.isFinite(scale) or scale <= 0) return error.InvalidScale;
    if (!std.math.isFinite(font.ascent) or !std.math.isFinite(font.descent) or !std.math.isFinite(font.line_gap)) return error.InvalidFont;
    if (font.ascent < 0 or font.descent > 0 or font.line_gap < 0) return error.InvalidFont;
    const rise = font.ascent * scale;
    if (!std.math.isFinite(rise)) return error.InvalidScale;
    const baseline_y = rect.y + rise;
    if (!std.math.isFinite(baseline_y)) return error.InvalidPosition;
    if (!std.math.isFinite(rect.x)) return error.InvalidPosition;
    return .{ rect.x, baseline_y };
}

/// Emit one line of text from a baseline origin. On any error, public geometry
/// counts and the previously mergeable command are restored, so no partial
/// string is visible through Buffer.view()/Context.drawDataView().
pub fn emitBaseline(buffer: *draw.Buffer, font: font_mod.Font, utf8: []const u8, baseline: [2]f32, scale: f32, color: u32, clip: draw.ClipRect) (Error || font_mod.Error || draw.Error)!Metrics {
    if (!std.math.isFinite(baseline[0]) or !std.math.isFinite(baseline[1])) return error.InvalidPosition;
    const metrics = try measure(font, utf8, scale);
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
        const resolved = font.resolve(decoded.codepoint) orelse return error.MissingGlyph;
        const x0 = pen_x + resolved.bearing_x * scale;
        const y0 = baseline[1] - resolved.bearing_y * scale;
        const x1 = x0 + resolved.width * scale;
        const y1 = y0 + resolved.height * scale;
        if (!std.math.isFinite(x0) or !std.math.isFinite(y0) or !std.math.isFinite(x1) or !std.math.isFinite(y1)) return error.InvalidPosition;
        if (resolved.width > 0 and resolved.height > 0) {
            try buffer.addTexturedQuad(
                .{ .{ x0, y0 }, .{ x1, y0 }, .{ x1, y1 }, .{ x0, y1 } },
                .{ .{ resolved.u0, resolved.v0 }, .{ resolved.u1, resolved.v0 }, .{ resolved.u1, resolved.v1 }, .{ resolved.u0, resolved.v1 } },
                color,
                font.texture,
                clip,
            );
        }
        pen_x += resolved.advance_x * scale;
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
    const test_font: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    var vertices: [4]draw.Vertex = undefined;
    var indices: [6]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    var buffer = draw.Buffer.init(&vertices, &indices, &commands);
    const clip: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try std.testing.expectError(error.OutOfCapacity, emitBaseline(&buffer, test_font, "AA", .{ 0, 10 }, 1, 0xffffffff, clip));
    try std.testing.expectEqual(@as(usize, 0), buffer.vertex_count);
    try std.testing.expectEqual(@as(usize, 0), buffer.index_count);
    try std.testing.expectEqual(@as(usize, 0), buffer.command_count);
}

test "utf8 decoder covers scalar boundaries and lengths" {
    const t = std.testing;
    try t.expectEqual(@as(u21, 0x00), (try decodeOne(&.{0x00})).codepoint);
    try t.expectEqual(@as(usize, 1), (try decodeOne(&.{0x00})).len);
    try t.expectEqual(@as(u21, 0x7F), (try decodeOne(&.{0x7F})).codepoint);
    try t.expectEqual(@as(u21, 0x80), (try decodeOne(&.{ 0xC2, 0x80 })).codepoint);
    try t.expectEqual(@as(usize, 2), (try decodeOne(&.{ 0xC2, 0x80 })).len);
    try t.expectEqual(@as(u21, 0x7FF), (try decodeOne(&.{ 0xDF, 0xBF })).codepoint);
    try t.expectEqual(@as(u21, 0x800), (try decodeOne(&.{ 0xE0, 0xA0, 0x80 })).codepoint);
    try t.expectEqual(@as(usize, 3), (try decodeOne(&.{ 0xE0, 0xA0, 0x80 })).len);
    try t.expectEqual(@as(u21, 0xD7FF), (try decodeOne(&.{ 0xED, 0x9F, 0xBF })).codepoint);
    try t.expectEqual(@as(u21, 0xE000), (try decodeOne(&.{ 0xEE, 0x80, 0x80 })).codepoint);
    try t.expectEqual(@as(u21, 0xFFFF), (try decodeOne(&.{ 0xEF, 0xBF, 0xBF })).codepoint);
    try t.expectEqual(@as(u21, 0x10000), (try decodeOne(&.{ 0xF0, 0x90, 0x80, 0x80 })).codepoint);
    try t.expectEqual(@as(u21, 0x10FFFF), (try decodeOne(&.{ 0xF4, 0x8F, 0xBF, 0xBF })).codepoint);
    try t.expectEqual(@as(usize, 4), (try decodeOne(&.{ 0xF4, 0x8F, 0xBF, 0xBF })).len);
    try t.expectEqual(@as(usize, 2), (try decodeOne("é")).len);
    try t.expectEqual(@as(u21, 0xE9), (try decodeOne("é")).codepoint);
}

test "utf8 decoder rejects truncated overlong and illegal leads" {
    const t = std.testing;
    try t.expectError(error.InvalidUtf8, decodeOne(&.{}));
    try t.expectError(error.InvalidUtf8, decodeOne(&.{0x80}));
    try t.expectError(error.InvalidUtf8, decodeOne(&.{0xBF}));
    try t.expectError(error.InvalidUtf8, decodeOne(&.{0xC1}));
    try t.expectError(error.InvalidUtf8, decodeOne(&.{0xFF}));
    try t.expectError(error.InvalidUtf8, decodeOne(&.{0xFE}));
    try t.expectError(error.InvalidUtf8, decodeOne(&.{0xC2}));
    try t.expectError(error.InvalidUtf8, decodeOne(&.{ 0xE2, 0x82 }));
    try t.expectError(error.InvalidUtf8, decodeOne(&.{ 0xF0, 0x9F, 0x98 }));
    try t.expectError(error.InvalidUtf8, decodeOne(&.{ 0xC2, 0x41 }));
    try t.expectError(error.InvalidUtf8, decodeOne(&.{ 0xE2, 0x28, 0xA6 }));
    try t.expectError(error.InvalidUtf8, decodeOne(&.{ 0xE0, 0x80, 0x80 }));
    try t.expectError(error.InvalidUtf8, decodeOne(&.{ 0xF0, 0x80, 0x80, 0x80 }));
    try t.expectError(error.InvalidUtf8, decodeOne(&.{ 0xED, 0xBF, 0xBF }));
    try t.expectError(error.InvalidUtf8, decodeOne(&.{ 0xF5, 0x80, 0x80, 0x80 }));
}

test "text measure handles empty long missing and invalid scale" {
    const t = std.testing;
    const glyphs = [_]font_mod.Glyph{glyph(65, 7, 6)};
    const test_font: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    const empty = try measure(test_font, "", 1);
    try t.expectEqual(@as(usize, 0), empty.glyph_count);
    try t.expectEqual(@as(f32, 0), empty.advance_x);
    try t.expectError(error.InvalidScale, measure(test_font, "A", 0));
    try t.expectError(error.InvalidScale, measure(test_font, "A", -1));
    try t.expectError(error.InvalidScale, measure(test_font, "A", std.math.inf(f32)));
    try t.expectError(error.InvalidScale, measure(test_font, "A", std.math.nan(f32)));
    try t.expectError(error.MissingGlyph, measure(test_font, "B", 1));
    const with_fallback: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1, .fallback = 65 };
    try with_fallback.validate();
    const fb = try measure(with_fallback, "B", 1);
    try t.expectEqual(@as(usize, 1), fb.glyph_count);
    try t.expectEqual(@as(f32, 7), fb.advance_x);
    var long: [256]u8 = undefined;
    @memset(&long, 'A');
    const lm = try measure(test_font, &long, 1);
    try t.expectEqual(@as(usize, 256), lm.glyph_count);
    try t.expectEqual(@as(f32, 256 * 7), lm.advance_x);
    const big_glyphs = [_]font_mod.Glyph{.{ .codepoint = 65, .advance_x = 3.4e38, .bearing_x = 0, .bearing_y = 0, .width = 1, .height = 1, .u0 = 0, .v0 = 0, .u1 = 1, .v1 = 1 }};
    const big_font: font_mod.Font = .{ .glyphs = &big_glyphs, .texture = 0, .ascent = 8, .descent = -2, .line_gap = 1 };
    try t.expectError(error.InvalidScale, measure(big_font, "A", 2));
    try t.expectError(error.InvalidUtf8, measure(test_font, "\xFF", 1));
}

test "text emission skips zero-area glyphs without geometry" {
    const t = std.testing;
    const zero = glyph(65, 7, 0);
    const normal = glyph(66, 7, 6);
    const glyphs = [_]font_mod.Glyph{ zero, normal };
    const test_font: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    try test_font.validate();
    var vertices: [4]draw.Vertex = undefined;
    var indices: [6]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    var buffer = draw.Buffer.init(&vertices, &indices, &commands);
    const clip: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    const m = try emitBaseline(&buffer, test_font, "AB", .{ 0, 10 }, 1, 0xffffffff, clip);
    try t.expectEqual(@as(usize, 2), m.glyph_count);
    try t.expectEqual(@as(f32, 14), m.advance_x);
    try t.expectEqual(@as(usize, 4), buffer.vertex_count);
    try t.expectEqual(@as(usize, 6), buffer.index_count);
    try t.expectEqual(@as(usize, 1), buffer.command_count);
}

test "text emission rejects non-finite baseline atomically" {
    const t = std.testing;
    const glyphs = [_]font_mod.Glyph{glyph(65, 7, 6)};
    const test_font: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    var vertices: [4]draw.Vertex = undefined;
    var indices: [6]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    var buffer = draw.Buffer.init(&vertices, &indices, &commands);
    const clip: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try t.expectError(error.InvalidPosition, emitBaseline(&buffer, test_font, "A", .{ std.math.inf(f32), 0 }, 1, 0xffffffff, clip));
    try t.expectEqual(@as(usize, 0), buffer.vertex_count);
    try t.expectError(error.InvalidPosition, emitBaseline(&buffer, test_font, "A", .{ 0, std.math.nan(f32) }, 1, 0xffffffff, clip));
    try t.expectEqual(@as(usize, 0), buffer.vertex_count);
    var bad = glyph(65, 7, 6);
    bad.bearing_x = std.math.inf(f32);
    const bad_glyphs = [_]font_mod.Glyph{bad};
    const bad_font: font_mod.Font = .{ .glyphs = &bad_glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    try t.expectError(error.InvalidPosition, emitBaseline(&buffer, bad_font, "A", .{ 0, 10 }, 1, 0xffffffff, clip));
    try t.expectEqual(@as(usize, 0), buffer.vertex_count);
    _ = try emitBaseline(&buffer, test_font, "A", .{ 0, 10 }, 1, 0xffffffff, clip);
    try t.expectEqual(@as(usize, 4), buffer.vertex_count);
}

test "text emission restores merged command on partial capacity failure" {
    const t = std.testing;
    const glyphs = [_]font_mod.Glyph{glyph(65, 7, 6)};
    const test_font: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    var vertices: [8]draw.Vertex = undefined;
    var indices: [12]u32 = undefined;
    var commands: [2]draw.Command = undefined;
    var buffer = draw.Buffer.init(&vertices, &indices, &commands);
    const clip: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try buffer.addRect(0, 0, 10, 10, 0xffffffff, 9, clip);
    const before = buffer.commands[0];
    try t.expectError(error.OutOfCapacity, emitBaseline(&buffer, test_font, "AA", .{ 0, 10 }, 1, 0xffffffff, clip));
    try t.expectEqual(@as(usize, 4), buffer.vertex_count);
    try t.expectEqual(@as(usize, 6), buffer.index_count);
    try t.expectEqual(@as(usize, 1), buffer.command_count);
    try t.expectEqualDeep(before, buffer.commands[0]);
    _ = try emitBaseline(&buffer, test_font, "A", .{ 0, 10 }, 1, 0xffffffff, clip);
    try t.expectEqual(@as(usize, 8), buffer.vertex_count);
    try t.expectEqual(@as(usize, 12), buffer.index_count);
    try t.expectEqual(@as(u32, 12), buffer.commands[0].index_count);
}

test "text emission fails cleanly when command capacity is exhausted" {
    const t = std.testing;
    const glyphs = [_]font_mod.Glyph{glyph(65, 7, 6)};
    const test_font: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    var vertices: [8]draw.Vertex = undefined;
    var indices: [12]u32 = undefined;
    var commands: [1]draw.Command = undefined;
    var buffer = draw.Buffer.init(&vertices, &indices, &commands);
    const clip: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 100, .max_y = 100 };
    try buffer.addRect(0, 0, 10, 10, 0xffffffff, 0, clip);
    const before = buffer.commands[0];
    try t.expectError(error.OutOfCapacity, emitBaseline(&buffer, test_font, "A", .{ 0, 10 }, 1, 0xffffffff, clip));
    try t.expectEqual(@as(usize, 4), buffer.vertex_count);
    try t.expectEqual(@as(usize, 6), buffer.index_count);
    try t.expectEqual(@as(usize, 1), buffer.command_count);
    try t.expectEqualDeep(before, buffer.commands[0]);
}

test "text emission batches long strings with valid indices" {
    const t = std.testing;
    const glyphs = [_]font_mod.Glyph{glyph(65, 7, 6)};
    const test_font: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    var vertices: [256 * 4]draw.Vertex = undefined;
    var indices: [256 * 6]u32 = undefined;
    var commands: [2]draw.Command = undefined;
    var buffer = draw.Buffer.init(&vertices, &indices, &commands);
    const clip: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 4096, .max_y = 4096 };
    var long: [256]u8 = undefined;
    @memset(&long, 'A');
    const m = try emitBaseline(&buffer, test_font, &long, .{ 0, 20 }, 1, 0xffffffff, clip);
    try t.expectEqual(@as(usize, 256), m.glyph_count);
    try t.expectEqual(@as(usize, 1024), buffer.vertex_count);
    try t.expectEqual(@as(usize, 1536), buffer.index_count);
    try t.expectEqual(@as(usize, 1), buffer.command_count);
    try t.expectEqual(@as(u32, 1536), buffer.commands[0].index_count);
    for (buffer.indexSlice()) |index| try t.expect(@as(usize, index) < buffer.vertex_count);
}

test "text line height scales font metrics and rejects invalid input" {
    const t = std.testing;
    const glyphs = [_]font_mod.Glyph{glyph(65, 7, 6)};
    const test_font: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    try t.expectEqual(@as(f32, 11), try lineHeight(test_font, 1));
    try t.expectEqual(@as(f32, 22), try lineHeight(test_font, 2));
    try t.expectError(error.InvalidScale, lineHeight(test_font, 0));
    try t.expectError(error.InvalidScale, lineHeight(test_font, -1));
    try t.expectError(error.InvalidScale, lineHeight(test_font, std.math.inf(f32)));
    var bad = test_font;
    bad.ascent = -1;
    try t.expectError(error.InvalidFont, lineHeight(bad, 1));
    bad = test_font;
    bad.descent = 1;
    try t.expectError(error.InvalidFont, lineHeight(bad, 1));
    bad = test_font;
    bad.line_gap = std.math.nan(f32);
    try t.expectError(error.InvalidFont, lineHeight(bad, 1));
    const zero_gap: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 0, .descent = 0, .line_gap = 0 };
    try t.expectError(error.InvalidFont, lineHeight(zero_gap, 1));
}

test "text line box combines width and height" {
    const t = std.testing;
    const glyphs = [_]font_mod.Glyph{ glyph(63, 5, 4), glyph(65, 7, 6) };
    const test_font: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1, .fallback = 63 };
    try test_font.validate();
    const box = try lineBox(test_font, "AB", 2);
    try t.expectEqual(@as(usize, 2), box.glyph_count);
    try t.expectEqual(@as(f32, 24), box.width);
    try t.expectEqual(@as(f32, 22), box.height);
    const empty = try lineBox(test_font, "", 1);
    try t.expectEqual(@as(f32, 0), empty.width);
    try t.expectEqual(@as(f32, 11), empty.height);
    const no_fallback_glyphs = [_]font_mod.Glyph{glyph(65, 7, 6)};
    const no_fallback: font_mod.Font = .{ .glyphs = &no_fallback_glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    try t.expectError(error.MissingGlyph, lineBox(no_fallback, "C", 1));
    try t.expectError(error.InvalidUtf8, lineBox(test_font, "\xFF", 1));
    try t.expectError(error.InvalidScale, lineBox(test_font, "A", 0));
}

test "text baseline sits on ascent offset inside layout rect" {
    const t = std.testing;
    const glyphs = [_]font_mod.Glyph{glyph(65, 7, 6)};
    const test_font: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    const rect: layout_mod.Rect = .{ .x = 15, .y = 20, .width = 90, .height = 11 };
    const base = try baselineInRect(rect, test_font, 1);
    try t.expectEqual(@as(f32, 15), base[0]);
    try t.expectEqual(@as(f32, 28), base[1]);
    const scaled = try baselineInRect(rect, test_font, 2);
    try t.expectEqual(@as(f32, 36), scaled[1]);
    try t.expectError(error.InvalidPosition, baselineInRect(.{ .x = std.math.nan(f32), .y = 0, .width = 10, .height = 10 }, test_font, 1));
    try t.expectError(error.InvalidPosition, baselineInRect(.{ .x = 0, .y = 0, .width = -1, .height = 10 }, test_font, 1));
    try t.expectError(error.InvalidScale, baselineInRect(rect, test_font, 0));
    const huge: layout_mod.Rect = .{ .x = 0, .y = 3.3e38, .width = 10, .height = 11 };
    try t.expectError(error.InvalidPosition, baselineInRect(huge, test_font, 1e37));
}

test "text layout integration emits two rows with spacing and batching" {
    const t = std.testing;
    const glyphs = [_]font_mod.Glyph{glyph(65, 7, 6)};
    const test_font: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    try test_font.validate();
    var stack: layout_mod.Stack = .{};
    try stack.push(.{ .x = 10, .y = 20, .width = 100, .height = 90 }, .{ .x = 5, .y = 3 });
    const height = try lineHeight(test_font, 1);
    const row0 = try stack.next(null, height);
    const row1 = try stack.next(null, height);
    try t.expectEqual(@as(f32, 20), row0.y);
    try t.expectEqual(@as(f32, 34), row1.y);
    try t.expectEqual(@as(f32, 15), row0.x);
    const base0 = try baselineInRect(row0, test_font, 1);
    const base1 = try baselineInRect(row1, test_font, 1);
    try t.expectEqual(@as(f32, 28), base0[1]);
    try t.expectEqual(@as(f32, 42), base1[1]);
    var vertices: [8]draw.Vertex = undefined;
    var indices: [12]u32 = undefined;
    var commands: [2]draw.Command = undefined;
    var buffer = draw.Buffer.init(&vertices, &indices, &commands);
    const clip: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 200, .max_y = 200 };
    _ = try emitBaseline(&buffer, test_font, "A", base0, 1, 0xffffffff, clip);
    _ = try emitBaseline(&buffer, test_font, "A", base1, 1, 0xffffffff, clip);
    try t.expectEqual(@as(usize, 8), buffer.vertex_count);
    try t.expectEqual(@as(usize, 1), buffer.command_count);
    try t.expectEqual(@as(f32, 16), buffer.vertices[0].x);
    try t.expectEqual(@as(f32, 21), buffer.vertices[0].y);
    try t.expectEqual(@as(f32, 16), buffer.vertices[4].x);
    try t.expectEqual(@as(f32, 35), buffer.vertices[4].y);
    try stack.pop();
    try stack.validateBalanced();
}

test "text layout overflow keeps metrics while clip stays on command" {
    const t = std.testing;
    const glyphs = [_]font_mod.Glyph{glyph(65, 7, 6)};
    const test_font: font_mod.Font = .{ .glyphs = &glyphs, .texture = 9, .ascent = 8, .descent = -2, .line_gap = 1 };
    const box = try lineBox(test_font, "AAAAAAAAAA", 1);
    try t.expectEqual(@as(f32, 70), box.width);
    var stack: layout_mod.Stack = .{};
    try stack.push(.{ .x = 0, .y = 0, .width = 20, .height = 40 }, .{});
    const row = try stack.next(null, box.height);
    try t.expect(box.width > row.width);
    const base = try baselineInRect(row, test_font, 1);
    var vertices: [40]draw.Vertex = undefined;
    var indices: [60]u32 = undefined;
    var commands: [2]draw.Command = undefined;
    var buffer = draw.Buffer.init(&vertices, &indices, &commands);
    const clip: draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 20, .max_y = 40 };
    _ = try emitBaseline(&buffer, test_font, "AAAAAAAAAA", base, 1, 0xffffffff, clip);
    try t.expectEqual(@as(usize, 40), buffer.vertex_count);
    try t.expectEqual(@as(usize, 1), buffer.command_count);
    try t.expectEqual(@as(f32, 0), buffer.commands[0].clip.min_x);
    try t.expectEqual(@as(f32, 20), buffer.commands[0].clip.max_x);
    try stack.pop();
}
