const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{ .name = "miniminion", .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    }) });

    exe.root_module.linkSystemLibrary("jsonnet", .{});
    exe.root_module.linkSystemLibrary("c", .{});
    // exe.linkage = .static;

    b.installArtifact(exe);
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
