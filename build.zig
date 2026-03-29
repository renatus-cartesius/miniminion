const std = @import("std");

pub fn build(b: *std.Build) void {
    const bpf_obj = b.addObject(.{
        .name = "trace_bpf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/trace.zig"),
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
        .{ .custom = "../epbf-out" },
        "trace_bpf.o",
    );

    b.getInstallStep().dependOn(&install_bpf.step);
}
