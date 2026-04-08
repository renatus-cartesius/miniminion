const std = @import("std");
const linux = std.os.linux;

const BPF_PROG_LOAD = 5;
const BPF_PROG_TYPE_SOCKET_FILTER = 1;

const bpf_obj = @embedFile("../bpf-out/trace_bpf.o");

pub fn main() !void {
    std.debug.print("BPF prog: {}\n", .{bpf_obj});
}
