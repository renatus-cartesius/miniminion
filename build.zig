const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{ .name = "miniminion", .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    }) });

    // jsonnet linkage
    exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/jsonnet-dist/include" });
    exe.root_module.addObjectFile(.{ .cwd_relative = "/opt/jsonnet-dist/lib/libjsonnet.a" });
    exe.root_module.addObjectFile(.{ .cwd_relative = "/opt/jsonnet-dist/lib/libstdc++.a" });
    exe.root_module.addObjectFile(.{ .cwd_relative = "/opt/jsonnet-dist/lib/libgcc_eh.a" });

    exe.root_module.linkSystemLibrary("c", .{});
    exe.root_module.linkSystemLibrary("bpf", .{});
    // exe.linkage = .static;

    exe.root_module.addIncludePath(.{ .cwd_relative = "src/bpf_sensors" });
    try buildBpfProgs(b, exe);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run miniminion binary");
    run_step.dependOn(&run_cmd.step);
}

// builds all src/bpf_sensors one by one
pub fn buildBpfProgs(b: *std.Build, exe: *std.Build.Step.Compile) !void {
    const sensors_to_build = [_][]const u8{
        "file",
        // " hello",
    };

    inline for (sensors_to_build) |sensor| {
        const src = "src/bpf_sensors/" ++ sensor ++ ".c";
        const out = "src/bpf_sensors/obj/" ++ sensor ++ ".o";

        const clang = b.addSystemCommand(&.{
            "clang",   "-g",
            "-O2",     "-D__TARGET_ARCH_x86",
            "-target", "bpf",
            "-c",      src,
            "-o",      out,
        });
        // b.getInstallStep().dependOn(&clang.step);
        exe.step.dependOn(&clang.step);
    }
}

// pub fn build(b: *std.Build) void {
//     const install_bpf = b.addInstallFileWithDir(
//         b.path("src/bpf_progs/compiled/foobar_write_detect.o"),
//         .{ .custom = "../src/bpf_progs/compiled" },
//         "foobar_write_detect.o",
//     );
//
//     const compile_bpf = b.addSystemCommand(&.{
//         "clang",
//         "-D__TARGET_ARCH_x86",
//         "-O2",
//         "-g",
//         "-target",
//         "bpf",
//         "-c",
//         "src/bpf_progs/foobar_write_detect.c",
//         "-o",
//         "src/bpf_progs/compiled/foobar_write_detect.o",
//     });
//     install_bpf.step.dependOn(&compile_bpf.step);
//
//     b.getInstallStep().dependOn(&install_bpf.step);
//
//     const target = b.standardTargetOptions(.{});
//     const optimize = b.standardOptimizeOption(.{});
//
//     const exe = b.addExecutable(.{
//         .name = "bpf-loader",
//         .root_module = b.createModule(.{
//             .root_source_file = b.path("src/main.zig"),
//             .target = target,
//             .optimize = optimize,
//         }),
//     });
//
//     exe.root_module.linkSystemLibrary("bpf", .{});
//     exe.root_module.linkSystemLibrary("c", .{});
//
//     b.installArtifact(exe);
//
//     const run_cmd = b.addRunArtifact(exe);
//     run_cmd.step.dependOn(b.getInstallStep());
//     b.getInstallStep().dependOn(&install_bpf.step);
//
//     const run_step = b.step("run", "Run the application");
//     run_step.dependOn(&run_cmd.step);
// }
