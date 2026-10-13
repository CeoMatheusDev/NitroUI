//! Deterministic headless workloads. No OS/window/GPU integration.
//! Build and run: zig build bench -Doptimize=ReleaseFast
//! This workload uses caller-owned fixed-capacity buffers and never requests an allocator.
//! Geometry, checksums and buffer-capacity metrics are deterministic.
//! Two cases per size: `rect` (raw geometry only), `widget` (input events,
//! vertical layout, integer-ID buttons exercising interaction and batching)
//! and `idstr` (same widget path but with hierarchical string IDs, covering
//! ID hashing and scope push/pop per widget).
//! Wall-clock timing uses a small monotonic-clock helper in this bench harness
//! only; the nitro_ui module itself has no clock dependency. Timing values are
//! machine-specific: warm-up frames are excluded, then per-frame nanoseconds
//! are collected over measured frames and summarized as min/median/p90/max.
const builtin = @import("builtin");
const std = @import("std");
const ui = @import("nitro_ui");

const warmup_frames: usize = 30;
const frames_per_case: usize = 300;
const counts = [_]usize{ 64, 256, 1024, 4096 };
const region: ui.draw.ClipRect = .{ .min_x = 0, .min_y = 0, .max_x = 2048, .max_y = 2048 };

const Workload = enum { rect, widget, idstr };

fn emitRects(ctx: *ui.Context, comptime count: usize) !void {
    for (0..count) |i| {
        const col = i % 64;
        const row = i / 64;
        const x: f32 = @as(f32, @floatFromInt(col)) * 30;
        const y: f32 = @as(f32, @floatFromInt(row)) * 24;
        try ctx.drawRect(x, y, x + 20, y + 16, 0xff_80_80_80, 0, region);
    }
}

/// Full widget path per frame: one pointer event, a vertical layout region,
/// and one integer-ID button per row. Pointer rests on the first button, so
/// hover resolves deterministically and all buttons batch into one command.
fn emitWidgets(ctx: *ui.Context, comptime count: usize) !void {
    const events = [_]ui.input_events.Event{
        .{ .pointer_move = .{ .x = 5, .y = 5 } },
    };
    try ctx.processEvents(&events);
    try ctx.pushLayout(
        .{ .x = 0, .y = 0, .width = 2048, .height = @as(f32, @floatFromInt(count)) * 20 },
        .{ .x = 0, .y = 0 },
    );
    for (0..count) |i| {
        const rect = try ctx.nextLayoutRect(null, 20);
        _ = try ctx.button(@as(u64, @intCast(i)), rect, region);
    }
    try ctx.popLayout();
}

fn emitCase(ctx: *ui.Context, comptime count: usize, comptime workload: Workload) !void {
    switch (workload) {
        .rect => try emitRects(ctx, count),
        .widget => try emitWidgets(ctx, count),
        .idstr => try emitIdWidgets(ctx, count),
    }
}

/// Same widget path as emitWidgets, but each button uses a hierarchical
/// string ID: one outer scope plus an integer scope per row. Covers ID
/// hashing and scope push/pop per widget on top of interaction and layout.
fn emitIdWidgets(ctx: *ui.Context, comptime count: usize) !void {
    const events = [_]ui.input_events.Event{
        .{ .pointer_move = .{ .x = 5, .y = 5 } },
    };
    try ctx.processEvents(&events);
    try ctx.pushLayout(
        .{ .x = 0, .y = 0, .width = 2048, .height = @as(f32, @floatFromInt(count)) * 20 },
        .{ .x = 0, .y = 0 },
    );
    try ctx.pushId("list");
    for (0..count) |i| {
        try ctx.pushIdInteger(@as(u64, @intCast(i)));
        const id = try ctx.widgetId("btn");
        const rect = try ctx.nextLayoutRect(null, 20);
        _ = try ctx.button(id, rect, region);
        try ctx.popId();
    }
    try ctx.popId();
    try ctx.popLayout();
}

fn sortU64(values: []u64) void {
    var i: usize = 1;
    while (i < values.len) : (i += 1) {
        const key = values[i];
        var j = i;
        while (j > 0 and values[j - 1] > key) {
            values[j] = values[j - 1];
            j -= 1;
        }
        values[j] = key;
    }
}

/// Monotonic nanoseconds for the bench harness only. Mirrors the clock-ID
/// mapping used by the Zig 0.17.0 standard library (CLOCK_MONOTONIC on Linux,
/// UPTIME_RAW on Darwin, performance counter on Windows, MONOTONIC on WASI).
/// Only validated on Linux; other branches follow std patterns untested here.
fn monoNanos() !u64 {
    switch (builtin.os.tag) {
        .windows => {
            const windows = std.os.windows;
            const qpf: u64 = qpf: {
                var freq: windows.LARGE_INTEGER = undefined;
                if (!windows.ntdll.RtlQueryPerformanceFrequency(&freq).toBool()) return error.ClockUnavailable;
                break :qpf @bitCast(freq);
            };
            const qpc: u64 = qpc: {
                var counter: windows.LARGE_INTEGER = undefined;
                if (!windows.ntdll.RtlQueryPerformanceCounter(&counter).toBool()) return error.ClockUnavailable;
                break :qpc @bitCast(counter);
            };
            return qpc / qpf * std.time.ns_per_s + (qpc % qpf) * std.time.ns_per_s / qpf;
        },
        .wasi => {
            var ns: std.os.wasi.timestamp_t = undefined;
            if (std.os.wasi.clock_time_get(.MONOTONIC, 1, &ns) != .SUCCESS) return error.ClockUnavailable;
            return ns;
        },
        else => {
            const clock_id: std.posix.clockid_t = switch (builtin.os.tag) {
                .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => std.posix.CLOCK.UPTIME_RAW,
                else => std.posix.CLOCK.MONOTONIC,
            };
            var ts: std.posix.timespec = undefined;
            if (std.posix.errno(std.posix.system.clock_gettime(clock_id, &ts)) != .SUCCESS) return error.ClockUnavailable;
            return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
        },
    }
}

fn runCase(comptime count: usize, comptime workload: Workload) !void {
    var vertices: [count * 4]ui.draw.Vertex = undefined;
    var indices: [count * 6]u32 = undefined;
    var commands: [1]ui.draw.Command = undefined;
    var ctx: ui.Context = .{};
    try ctx.setGeometryStorage(&vertices, &indices, &commands);

    const input: ui.FrameInput = .{
        .delta_seconds = 1.0 / 60.0,
        .display_size = .{ .x = 2048, .y = 2048 },
    };

    // Warm-up: stabilize caches/branch prediction; excluded from timing.
    for (0..warmup_frames) |_| {
        try ctx.beginFrame(input);
        try emitCase(&ctx, count, workload);
        try ctx.endFrame();
        _ = try ctx.drawDataView();
        try ctx.releaseFrame();
    }

    var times: [frames_per_case]u64 = undefined;
    var checksum: u64 = 0;
    for (0..frames_per_case) |f| {
        const start = try monoNanos();
        try ctx.beginFrame(input);
        try emitCase(&ctx, count, workload);
        try ctx.endFrame();
        const data = try ctx.drawDataView();
        if (data.vertices.len != count * 4 or data.indices.len != count * 6 or data.commands.len != 1)
            return error.InvalidBenchmarkOutput;
        // Verify that the one-command batching contract covers all indices.
        if (data.commands[0].index_count != count * 6)
            return error.InvalidBenchmarkOutput;
        checksum +%= @as(u64, @intCast(data.vertices.len));
        checksum +%= @as(u64, @intCast(data.indices.len));
        checksum +%= @as(u64, @intCast(data.commands.len));
        try ctx.releaseFrame();
        const end = try monoNanos();
        times[f] = end - start;
    }
    sortU64(times[0..]);
    const ns_min = times[0];
    const ns_med = times[frames_per_case / 2];
    const ns_p90 = times[frames_per_case * 9 / 10];
    const ns_max = times[frames_per_case - 1];
    const geometry_bytes = @sizeOf(ui.draw.Vertex) * count * 4 +
        @sizeOf(u32) * count * 6 + @sizeOf(ui.draw.Command);
    std.debug.print("case={s} widgets={d} frames={d} vertices/frame={d} indices/frame={d} commands/frame=1 checksum={d} geometry_capacity_bytes={d} bytes/widget={d} (excluding command) ns_frame_min={d} ns_frame_med={d} ns_frame_p90={d} ns_frame_max={d} ns_widget_med={d}\n", .{
        @tagName(workload), count,                                          frames_per_case, count * 4, count * 6, checksum,
        geometry_bytes,     @sizeOf(ui.draw.Vertex) * 4 + @sizeOf(u32) * 6, ns_min,          ns_med,    ns_p90,    ns_max,
        ns_med / count,
    });
}

pub fn main() !void {
    inline for (counts) |count| try runCase(count, .rect);
    inline for (counts) |count| try runCase(count, .widget);
    inline for (counts) |count| try runCase(count, .idstr);
}
