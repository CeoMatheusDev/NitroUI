//! Headless engine-side integration contract; no window, GPU, or OS input.
//! Compile via `zig build integration` so the nitro_ui module is injected.
const ui = @import("nitro_ui");

const HostError = error{ InvalidVertexCount, InvalidIndexCount, InvalidCommandCount, InvalidCommandRange, InvalidVertexReference, InvalidClip, InvalidTexture, InvalidFrameReuse };

/// Synchronous stand-in for the engine renderer. Does not retain borrowed slices.
const EngineRenderer = struct {
    frames_consumed: usize = 0,
    total_indices: usize = 0,

    fn submit(self: *EngineRenderer, view: ui.draw.View, expected_vertices: usize, expected_indices: usize) HostError!void {
        if (view.vertices.len != expected_vertices) return error.InvalidVertexCount;
        if (view.indices.len != expected_indices) return error.InvalidIndexCount;
        if (view.commands.len != 1) return error.InvalidCommandCount;
        var covered: usize = 0;
        for (view.commands) |cmd| {
            const first: usize = @intCast(cmd.first_index);
            const count: usize = @intCast(cmd.index_count);
            if (first != covered or count > view.indices.len - covered) return error.InvalidCommandRange;
            if (cmd.texture != 0) return error.InvalidTexture;
            if (cmd.clip.min_x != 0 or cmd.clip.min_y != 0 or cmd.clip.max_x != 800 or cmd.clip.max_y != 600) return error.InvalidClip;
            covered += count;
        }
        if (covered != view.indices.len) return error.InvalidCommandRange;
        for (view.indices) |index| {
            if (@as(usize, index) >= view.vertices.len) return error.InvalidVertexReference;
        }
        self.frames_consumed += 1;
        self.total_indices += view.indices.len;
    }
};

pub fn main() !void {
    var vertices: [64]ui.draw.Vertex = undefined;
    var indices: [96]u32 = undefined;
    var commands: [4]ui.draw.Command = undefined;
    var ctx: ui.Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);

    const clip: ui.draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 800, .max_y = 600 };
    var checked = false;
    var volume: f32 = 0.5;
    var renderer: EngineRenderer = .{};

    for (0..40) |frame| {
        // The engine owns time, display metrics, event stream, and render storage.
        try ctx.beginFrame(.{
            .delta_seconds = 1.0 / 60.0,
            .display_size = .{ .x = 800, .y = 600 },
        });
        const pointer_x: f32 = if (frame % 2 == 0) 40 else 700;
        try ctx.processEvents(&.{.{ .pointer_move = .{ .x = pointer_x, .y = 30 } }});
        try ctx.pushLayout(.{ .x = 10, .y = 10, .width = 200, .height = 200 }, .{ .x = 0, .y = 6 });
        const b = try ctx.nextLayoutRect(null, 28);
        const c = try ctx.nextLayoutRect(null, 20);
        const s = try ctx.nextLayoutRect(null, 20);
        _ = try ctx.button(try ctx.widgetId("play"), b, clip);
        _ = try ctx.checkbox(try ctx.widgetId("muted"), c, &checked, clip);
        _ = try ctx.sliderFloat(try ctx.widgetId("volume"), s, &volume, 0, 1, clip);
        try ctx.popLayout();
        try ctx.endFrame();

        // Synchronous consumption completes BEFORE releaseFrame().
        const view = try ctx.drawDataView();
        try renderer.submit(view, 16, 24);
        try ctx.releaseFrame();
        if (ctx.state != .idle) return error.InvalidFrameReuse;
    }
    if (renderer.frames_consumed != 40 or renderer.total_indices != 960) return error.InvalidFrameReuse;
}
