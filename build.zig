const std = @import("std");

fn addJsonnet(module: *std.Build.Module) void {
    module.addIncludePath(.{ .cwd_relative = "/opt/jsonnet-dist/include" });
    module.addObjectFile(.{ .cwd_relative = "/opt/jsonnet-dist/lib/libjsonnet.a" });
    module.addObjectFile(.{ .cwd_relative = "/opt/jsonnet-dist/lib/libstdc++.a" });
    module.addObjectFile(.{ .cwd_relative = "/opt/jsonnet-dist/lib/libgcc_eh.a" });
}

fn addBpf(module: *std.Build.Module) void {
    module.addIncludePath(.{ .cwd_relative = "src/bpf" });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const agent = b.addExecutable(.{ .name = "minim-agent", .root_module = b.createModule(.{
        .root_source_file = b.path("src/agent_main.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    agent.linkage = .static;
    agent.root_module.linkSystemLibrary("c", .{});
    addJsonnet(agent.root_module);
    addBpf(agent.root_module);
    try buildBpfProgs(b, agent);
    b.installArtifact(agent);

    const controller = b.addExecutable(.{ .name = "minim-controller", .root_module = b.createModule(.{
        .root_source_file = b.path("src/controller_main.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    controller.linkage = .static;
    controller.root_module.linkSystemLibrary("c", .{});
    b.installArtifact(controller);

    const run_agent = b.addRunArtifact(agent);
    const run_step = b.step("run-agent", "Run minim-agent");
    run_step.dependOn(&run_agent.step);

    const run_controller = b.addRunArtifact(controller);
    const run_ctrl_step = b.step("run-controller", "Run minim-controller (dummy)");
    run_ctrl_step.dependOn(&run_controller.step);

    const test_step = b.step("test", "Run all tests");
    const test_files = [_][]const u8{ "src/dag.zig", "src/resource.zig" };
    for (test_files, 0..) |file, i| {
        const test_exe = b.addTest(.{
            .name = b.fmt("test-{d}", .{i}),
            .root_module = b.createModule(.{
                .root_source_file = b.path(file),
                .target = target,
                .optimize = optimize,
            }),
        });
        test_exe.root_module.linkSystemLibrary("c", .{});
        test_exe.linkage = .static;
        test_step.dependOn(&test_exe.step);
    }
}

fn buildBpfProgs(b: *std.Build, exe: *std.Build.Step.Compile) !void {
    const progs_to_build = [_][]const u8{
        "file_sensor",
    };

    inline for (progs_to_build) |prog| {
        const src = "src/bpf/" ++ prog ++ ".c";
        const out = "src/bpf/obj/" ++ prog ++ ".o";

        const clang = b.addSystemCommand(&.{
            "clang",   "-g",
            "-O2",     "-D__TARGET_ARCH_x86",
            "-target", "bpf",
            "-c",      src,
            "-o",      out,
        });
        exe.step.dependOn(&clang.step);
    }
}

