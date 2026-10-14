//! Full engine-side integration cycle; headless, no window, GPU, or OS input.
//! Compile and run via `zig build integration` (Debug and ReleaseFast).
//! Demonstrates: storage setup, text rendering, button click, Tab focus,
//! Unicode text input, display resize, small-buffer failure with recovery,
//! draw-data validation, and two independent contexts.
const std = @import("std");
const ui = @import("nitro_ui");

const HostError = error{
    InvalidVertexCount,
    InvalidCommandRange,
    InvalidVertexReference,
    InvalidTexture,
    InvalidClip,
    InvalidFrameReuse,
    UnexpectedGeometry,
    UnexpectedFocus,
    UnexpectedText,
    UnexpectedClick,
    ExpectedFailureMissing,
};

/// Synchronous stand-in for the engine renderer. Retains nothing.
const EngineRenderer = struct {
    frames_consumed: usize = 0,
    miss_texture: u64 = 0,
    clip: ui.draw.ClipRect = undefined,

    fn submit(self: *EngineRenderer, view: ui.draw.View) HostError!void {
        if (view.commands.len == 0) return error.InvalidVertexCount;
        var covered: usize = 0;
        for (view.commands) |cmd| {
            const first: usize = @intCast(cmd.first_index);
            const count: usize = @intCast(cmd.index_count);
            if (first != covered or count > view.indices.len - covered) return error.InvalidCommandRange;
            if (cmd.texture != 0 and cmd.texture != self.miss_texture) return error.InvalidTexture;
            if (cmd.clip.min_x < self.clip.min_x or cmd.clip.min_y < self.clip.min_y or
                cmd.clip.max_x > self.clip.max_x or cmd.clip.max_y > self.clip.max_y or
                cmd.clip.max_x < cmd.clip.min_x or cmd.clip.max_y < cmd.clip.min_y) return error.InvalidClip;
            covered += count;
        }
        if (covered != view.indices.len) return error.InvalidCommandRange;
        for (view.indices) |index| {
            if (@as(usize, index) >= view.vertices.len) return error.InvalidVertexReference;
        }
        self.frames_consumed += 1;
    }
};

fn unitGlyph(codepoint: u21, advance: f32) ui.font.Glyph {
    return .{
        .codepoint = codepoint,
        .advance_x = advance,
        .bearing_x = 0,
        .bearing_y = 8,
        .width = 6,
        .height = 9,
        .u0 = 0,
        .v0 = 0,
        .u1 = 1,
        .v1 = 1,
    };
}

pub fn main() !void {
    // Engine-owned font atlas descriptor: sorted glyphs, validated once.
    const glyphs = [_]ui.font.Glyph{
        .{ .codepoint = 0x20, .advance_x = 4, .bearing_x = 0, .bearing_y = 0, .width = 0, .height = 0, .u0 = 0, .v0 = 0, .u1 = 0, .v1 = 0 },
        unitGlyph(0x3f, 7),
        unitGlyph(0x48, 7),
        unitGlyph(0x69, 5),
    };
    const font: ui.font.Font = .{ .glyphs = &glyphs, .texture = 7, .ascent = 9, .descent = -3, .line_gap = 2, .fallback = 0x3f };
    try font.validate();

    // Primary context: engine-owned geometry, navigation, and editor storage.
    var vertices: [256]ui.draw.Vertex = undefined;
    var indices: [384]u32 = undefined;
    var commands: [16]ui.draw.Command = undefined;
    var nav_prev: [8]ui.ids.Id = undefined;
    var nav_cur: [8]ui.ids.Id = undefined;
    var ctx: ui.Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);
    try ctx.setNavigationStorage(&nav_prev, &nav_cur);

    var edit_storage: [32]u8 = undefined;
    var editor = try ui.text_edit.Buffer.init(&edit_storage, "");
    var checked = false;
    var volume: f32 = 0.5;
    var renderer: EngineRenderer = .{ .miss_texture = 7, .clip = .{ .min_x = 0, .min_y = 0, .max_x = 800, .max_y = 600 } };

    const btn_rect: ui.layout.Rect = .{ .x = 10, .y = 10, .width = 120, .height = 28 };
    const chk_rect: ui.layout.Rect = .{ .x = 10, .y = 44, .width = 120, .height = 20 };
    const sld_rect: ui.layout.Rect = .{ .x = 10, .y = 70, .width = 200, .height = 32 };
    const fld_rect: ui.layout.Rect = .{ .x = 10, .y = 108, .width = 200, .height = 24 };

    // Frame 0: layout-driven label plus widgets; structural draw-data check.
    try ctx.beginFrame(.{ .delta_seconds = 1.0 / 60.0, .display_size = .{ .x = 800, .y = 600 } });
    try ctx.processEvents(&.{.{ .pointer_move = .{ .x = 700, .y = 500 } }});
    try ctx.pushLayout(.{ .x = 10, .y = 140, .width = 200, .height = 60 }, .{ .x = 0, .y = 4 });
    const title = try ctx.label(font, "Hi", 1, 0xffffffff, renderer.clip);
    if (title.width != 12) return error.UnexpectedGeometry;
    try ctx.popLayout();
    _ = try ctx.button(try ctx.widgetId("ok"), btn_rect, renderer.clip);
    _ = try ctx.checkbox(try ctx.widgetId("muted"), chk_rect, &checked, renderer.clip);
    _ = try ctx.sliderFloat(try ctx.widgetId("volume"), sld_rect, &volume, 0, 1, renderer.clip);
    try ctx.endFrame();
    try renderer.submit(try ctx.drawDataView());
    try ctx.releaseFrame();
    if (ctx.state != .idle) return error.InvalidFrameReuse;

    // Frame 1: press and release over the button in one batch clicks it.
    try ctx.beginFrame(.{ .delta_seconds = 1.0 / 60.0, .display_size = .{ .x = 800, .y = 600 } });
    try ctx.processEvents(&.{
        .{ .pointer_move = .{ .x = 20, .y = 20 } },
        .{ .pointer_button = .{ .button = .primary, .down = true } },
        .{ .pointer_button = .{ .button = .primary, .down = false } },
    });
    if (!try ctx.button(try ctx.widgetId("ok"), btn_rect, renderer.clip)) return error.UnexpectedClick;
    _ = try ctx.checkbox(try ctx.widgetId("muted"), chk_rect, &checked, renderer.clip);
    _ = try ctx.sliderFloat(try ctx.widgetId("volume"), sld_rect, &volume, 0, 1, renderer.clip);
    try ctx.endFrame();
    try renderer.submit(try ctx.drawDataView());
    try ctx.releaseFrame();

    // Frame 2: Tab advances focus from the button to the checkbox.
    try ctx.beginFrame(.{ .delta_seconds = 1.0 / 60.0, .display_size = .{ .x = 800, .y = 600 } });
    try ctx.requestFocus(try ctx.widgetId("ok"));
    _ = try ctx.button(try ctx.widgetId("ok"), btn_rect, renderer.clip);
    _ = try ctx.checkbox(try ctx.widgetId("muted"), chk_rect, &checked, renderer.clip);
    _ = try ctx.sliderFloat(try ctx.widgetId("volume"), sld_rect, &volume, 0, 1, renderer.clip);
    try ctx.endFrame();
    try ctx.releaseFrame();
    try ctx.beginFrame(.{ .delta_seconds = 1.0 / 60.0, .display_size = .{ .x = 800, .y = 600 } });
    try ctx.processEvents(&.{.{ .key = .{ .code = ui.input_events.NavigationKey.tab, .down = true } }});
    _ = try ctx.button(try ctx.widgetId("ok"), btn_rect, renderer.clip);
    _ = try ctx.checkbox(try ctx.widgetId("muted"), chk_rect, &checked, renderer.clip);
    _ = try ctx.sliderFloat(try ctx.widgetId("volume"), sld_rect, &volume, 0, 1, renderer.clip);
    const muted_id = try ctx.widgetId("muted");
    try ctx.endFrame();
    if (ctx.focusedId() != muted_id) return error.UnexpectedFocus;
    try ctx.releaseFrame();

    // Frame 3: focused text field consumes Unicode scalar events.
    try ctx.beginFrame(.{ .delta_seconds = 1.0 / 60.0, .display_size = .{ .x = 800, .y = 600 } });
    try ctx.requestFocus(try ctx.widgetId("field"));
    const consumed = try ctx.inputText(try ctx.widgetId("field"), fld_rect, &editor, &.{ .{ .text = 'H' }, .{ .text = 'i' } }, false, font, 1, 0xffffffff, renderer.clip);
    if (consumed != 2) return error.UnexpectedText;
    if (!std.mem.eql(u8, editor.view(), "Hi")) return error.UnexpectedText;
    try ctx.endFrame();
    try renderer.submit(try ctx.drawDataView());
    try ctx.releaseFrame();

    // Frame 4: display resize; draw-data access before endFrame is rejected.
    renderer.clip = .{ .min_x = 0, .min_y = 0, .max_x = 1280, .max_y = 720 };
    try ctx.beginFrame(.{ .delta_seconds = 1.0 / 60.0, .display_size = .{ .x = 1280, .y = 720 } });
    try ctx.pushLayout(.{ .x = 10, .y = 140, .width = 200, .height = 60 }, .{ .x = 0, .y = 4 });
    _ = try ctx.label(font, editor.view(), 1, 0xffffffff, renderer.clip);
    try ctx.popLayout();
    if (ctx.drawDataView()) |_| return error.ExpectedFailureMissing else |err| {
        if (err != error.InvalidFrameState) return err;
    }
    try ctx.endFrame();
    try renderer.submit(try ctx.drawDataView());
    try ctx.releaseFrame();

    // Frame 5: undersized buffers fail atomically and the frame still closes.
    var tiny_v: [4]ui.draw.Vertex = undefined;
    var tiny_i: [6]u32 = undefined;
    var tiny_c: [1]ui.draw.Command = undefined;
    var tiny: ui.Context = .{};
    try tiny.setGeometryStorage(&tiny_v, &tiny_i, &tiny_c);
    try tiny.beginFrame(.{ .delta_seconds = 1.0 / 60.0, .display_size = .{ .x = 800, .y = 600 } });
    try tiny.pushLayout(.{ .x = 0, .y = 0, .width = 400, .height = 100 }, .{});
    if (tiny.label(font, "Hi Hi Hi", 1, 0xffffffff, renderer.clip)) |_| {
        return error.ExpectedFailureMissing;
    } else |err| {
        if (err != error.OutOfCapacity) return err;
    }
    if (tiny.geometry.?.vertex_count != 0 or tiny.geometry.?.command_count != 0) return error.UnexpectedGeometry;
    try tiny.popLayout();
    try tiny.endFrame();
    try tiny.releaseFrame();
    if (tiny.state != .idle) return error.InvalidFrameReuse;

    // Frame 6: primary context is unaffected by the tiny failure.
    try ctx.beginFrame(.{ .delta_seconds = 1.0 / 60.0, .display_size = .{ .x = 1280, .y = 720 } });
    try ctx.pushLayout(.{ .x = 10, .y = 140, .width = 200, .height = 60 }, .{ .x = 0, .y = 4 });
    _ = try ctx.label(font, "Hi", 1, 0xffffffff, renderer.clip);
    try ctx.popLayout();
    try ctx.endFrame();
    try renderer.submit(try ctx.drawDataView());
    try ctx.releaseFrame();

    if (renderer.frames_consumed != 5) return error.InvalidFrameReuse;
}
