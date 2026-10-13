//! Engine-owned, immutable font metrics contract. No rasterization or allocations.
const std = @import("std");

pub const Error = error{ InvalidFont, InvalidGlyph, UnsortedGlyphs, MissingGlyph };

/// One Unicode scalar value. UVs are normalized atlas coordinates.
/// Bearing and advance are expressed in logical UI pixels at the supplied font size.
pub const Glyph = struct {
    codepoint: u21,
    advance_x: f32,
    bearing_x: f32,
    bearing_y: f32,
    width: f32,
    height: f32,
    u0: f32,
    v0: f32,
    u1: f32,
    v1: f32,
};

/// The caller owns glyph storage and the texture identified by `texture`.
/// Glyphs must be sorted by strictly increasing codepoint, without duplicates.
/// Neither this descriptor nor its slices retain or manage GPU resources.
pub const Font = struct {
    glyphs: []const Glyph,
    texture: u64,
    ascent: f32,
    descent: f32,
    line_gap: f32,
    fallback: ?u21 = null,

    pub fn validate(self: Font) Error!void {
        if (!finite(self.ascent) or !finite(self.descent) or !finite(self.line_gap)) return error.InvalidFont;
        if (self.ascent < 0 or self.descent > 0 or self.line_gap < 0) return error.InvalidFont;
        const line_height = self.ascent - self.descent + self.line_gap;
        if (!finite(line_height) or line_height <= 0) return error.InvalidFont;
        var previous: ?u21 = null;
        for (self.glyphs) |glyph| {
            if (!scalar(glyph.codepoint) or !finite(glyph.advance_x) or glyph.advance_x < 0 or
                !finite(glyph.bearing_x) or !finite(glyph.bearing_y) or
                !finite(glyph.width) or glyph.width < 0 or !finite(glyph.height) or glyph.height < 0 or
                !uv(glyph.u0) or !uv(glyph.v0) or !uv(glyph.u1) or !uv(glyph.v1) or
                glyph.u0 > glyph.u1 or glyph.v0 > glyph.v1) return error.InvalidGlyph;
            if (previous) |p| {
                if (glyph.codepoint <= p) return error.UnsortedGlyphs;
            }
            previous = glyph.codepoint;
        }
        if (self.fallback) |cp| {
            if (!scalar(cp) or self.find(cp) == null) return error.MissingGlyph;
        }
    }

    /// Binary search, O(log n). Call validate() when attaching new font data.
    pub fn find(self: Font, codepoint: u21) ?*const Glyph {
        var lo: usize = 0;
        var hi: usize = self.glyphs.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.glyphs[mid].codepoint < codepoint) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        if (lo < self.glyphs.len and self.glyphs[lo].codepoint == codepoint) return &self.glyphs[lo];
        return null;
    }

    /// Resolve missing codepoints through the optional fallback glyph.
    pub fn resolve(self: Font, codepoint: u21) ?*const Glyph {
        return self.find(codepoint) orelse if (self.fallback) |cp| self.find(cp) else null;
    }
};

fn finite(value: f32) bool {
    return std.math.isFinite(value);
}
fn uv(value: f32) bool {
    return finite(value) and value >= 0 and value <= 1;
}
fn scalar(cp: u21) bool {
    return cp <= 0x10ffff and !(cp >= 0xd800 and cp <= 0xdfff);
}

fn sample(cp: u21) Glyph {
    return .{ .codepoint = cp, .advance_x = 8, .bearing_x = 0, .bearing_y = 8, .width = 8, .height = 10, .u0 = 0, .v0 = 0, .u1 = 0.5, .v1 = 0.5 };
}

test "font contract validates sorted glyphs and fallback lookup" {
    const glyphs = [_]Glyph{ sample(63), sample(65), sample(0x1f600) };
    const font: Font = .{ .glyphs = &glyphs, .texture = 7, .ascent = 9, .descent = -3, .line_gap = 2, .fallback = 63 };
    try font.validate();
    try std.testing.expectEqual(@as(u21, 65), font.find(65).?.codepoint);
    try std.testing.expect(font.find(66) == null);
    try std.testing.expectEqual(@as(u21, 63), font.resolve(66).?.codepoint);
}

test "font contract rejects duplicates, invalid scalars and missing fallback" {
    const duplicates = [_]Glyph{ sample(65), sample(65) };
    try std.testing.expectError(error.UnsortedGlyphs, (Font{ .glyphs = &duplicates, .texture = 0, .ascent = 8, .descent = -2, .line_gap = 0 }).validate());
    const surrogate = [_]Glyph{sample(0xd800)};
    try std.testing.expectError(error.InvalidGlyph, (Font{ .glyphs = &surrogate, .texture = 0, .ascent = 8, .descent = -2, .line_gap = 0 }).validate());
    const valid = [_]Glyph{sample(65)};
    try std.testing.expectError(error.MissingGlyph, (Font{ .glyphs = &valid, .texture = 0, .ascent = 8, .descent = -2, .line_gap = 0, .fallback = 63 }).validate());
}

test "font contract rejects invalid metrics and UV" {
    const valid = [_]Glyph{sample(65)};
    try std.testing.expectError(error.InvalidFont, (Font{ .glyphs = &valid, .texture = 0, .ascent = 0, .descent = 0, .line_gap = 0 }).validate());
    var bad = sample(65);
    bad.u1 = 1.5;
    const glyphs = [_]Glyph{bad};
    try std.testing.expectError(error.InvalidGlyph, (Font{ .glyphs = &glyphs, .texture = 0, .ascent = 8, .descent = -2, .line_gap = 0 }).validate());
}
