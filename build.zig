const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("nitro_ui", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{ .root_module = module });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run NitroUI unit tests");
    test_step.dependOn(&run_tests.step);

    const bench_module = b.createModule(.{
        .root_source_file = b.path("bench/headless.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "nitro_ui", .module = module }},
    });

    const bench_exe = b.addExecutable(.{
        .name = "bench_headless",
        .root_module = bench_module,
    });
    b.installArtifact(bench_exe);

    // Independent engine-side consumer: imports only the public nitro_ui module.
    const integration_module = b.createModule(.{
        .root_source_file = b.path("examples/engine_host.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "nitro_ui", .module = module }},
    });
    const integration_exe = b.addExecutable(.{
        .name = "engine_host",
        .root_module = integration_module,
    });
    const run_integration = b.addRunArtifact(integration_exe);
    const integration_step = b.step("integration", "Run engine-side headless integration contract");
    integration_step.dependOn(&run_integration.step);

    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Build and run headless benchmark");
    bench_step.dependOn(&run_bench.step);
}
