const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{ .name = "miniminion", .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    }) });

    exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/jsonnet-dist/include" });
    exe.root_module.addObjectFile(.{ .cwd_relative = "/opt/jsonnet-dist/lib/libjsonnet.a" });
    exe.root_module.addObjectFile(.{ .cwd_relative = "/opt/jsonnet-dist/lib/libstdc++.a" });
    exe.root_module.addObjectFile(.{ .cwd_relative = "/opt/jsonnet-dist/lib/libgcc_eh.a" });

    exe.root_module.linkSystemLibrary("c", .{});
    exe.linkage = .static;

    exe.root_module.addIncludePath(.{ .cwd_relative = "src/bpf" });
    try buildBpfProgs(b, exe);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run miniminion binary");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run all tests");
    const test_files = [_][]const u8{ "src/modules/package.zig", "src/dag.zig", "src/resource.zig" };
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