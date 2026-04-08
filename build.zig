const std = @import("std");

pub fn build(b: *std.Build) void {
    const bpf_obj = b.addObject(.{
        .name = "trace_bpf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bpf_progs/trace.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .bpfel,
                .os_tag = .freestanding,
            }),
            .optimize = .ReleaseSafe,
        }),
    });

    bpf_obj.root_module.strip = false;

    const install_bpf = b.addInstallFileWithDir(
        bpf_obj.getEmittedBin(),
        .{ .custom = "../bpf-out" },
        "trace_bpf.o",
    );

    b.getInstallStep().dependOn(&install_bpf.step);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "bpf-loader",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.linkSystemLibrary("bpf", .{});
    exe.root_module.linkSystemLibrary("elf", .{});
    exe.root_module.link_libc = true;

    b.installArtifact(exe);
}
