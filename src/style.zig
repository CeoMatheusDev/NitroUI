//! Per-context visual configuration. Colors use draw.Vertex RGBA8 packing:
//! numeric 0xAABBGGRR. No allocations or global mutable state.
const std = @import("std");

pub const Palette = struct {
    button: u32,
    button_hovered: u32,
    button_active: u32,
    checkbox: u32,
    checkbox_hovered: u32,
    checkmark: u32,
    slider_track: u32,
    slider_fill: u32,
};

pub const Style = struct {
    colors: Palette,
    /// Reserved for future layout/style integration; current widgets use caller-provided bounds.
    item_spacing_x: f32 = 8,
    item_spacing_y: f32 = 6,
    frame_padding_x: f32 = 8,
    frame_padding_y: f32 = 6,

    pub fn dark() Style {
        return .{ .colors = .{
            .button = 0xff785938,
            .button_hovered = 0xffa07548,
            .button_active = 0xff805c36,
            .checkbox = 0xff393939,
            .checkbox_hovered = 0xff555555,
            .checkmark = 0xff67c98b,
            .slider_track = 0xff393939,
            .slider_fill = 0xffb58957,
        } };
    }

    pub fn light() Style {
        return .{ .colors = .{
            .button = 0xffd5b89b,
            .button_hovered = 0xffe5c9aa,
            .button_active = 0xffc4a184,
            .checkbox = 0xffe0e0e0,
            .checkbox_hovered = 0xffcacaca,
            .checkmark = 0xff458c42,
            .slider_track = 0xffd0d0d0,
            .slider_fill = 0xffa96c38,
        } };
    }

    pub fn valid(self: Style) bool {
        return finiteNonNegative(self.item_spacing_x) and
            finiteNonNegative(self.item_spacing_y) and
            finiteNonNegative(self.frame_padding_x) and
            finiteNonNegative(self.frame_padding_y);
    }
};

fn finiteNonNegative(x: f32) bool {
    return std.math.isFinite(x) and x >= 0;
}

test "built-in themes are valid and distinct" {
    const testing = std.testing;
    try testing.expect(Style.dark().valid());
    try testing.expect(Style.light().valid());
    try testing.expect(Style.dark().colors.button != Style.light().colors.button);
}

test "invalid spacing and padding are rejected" {
    const testing = std.testing;
    var s = Style.dark();
    s.item_spacing_x = -1;
    try testing.expect(!s.valid());
    s = Style.dark();
    s.frame_padding_y = std.math.inf(f32);
    try testing.expect(!s.valid());
}
