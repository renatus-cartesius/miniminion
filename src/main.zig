const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;

const c = @cImport({
    @cInclude("bpf/libbpf.h");
});

pub fn main() !void {
    const bpf_obj_path = "src/bpf_progs/compiled/trace_bpf.o";

    const obj = c.bpf_object__open(bpf_obj_path) orelse {
        std.debug.print("Failed to open BPF object\n", .{});
        return error.BpfOpenFailed;
    };
    defer c.bpf_object__close(obj);

    if (c.bpf_object__load(obj) < 0) {
        std.debug.print("Error loading BPF into kernel\n", .{});
        return error.BpfLoadFailed;
    }

    const prog = c.bpf_object__find_program_by_name(obj, "trace_execve") orelse {
        std.debug.print("Failed to find program 'trace_execve'\n", .{});
        return error.ProgramNotFound;
    };
    const link = c.bpf_program__attach(prog) orelse {
        std.debug.print("Error attaching program\n", .{});
        return error.BpfAttachFailed;
    };
    defer _ = c.bpf_link__destroy(link);

    std.debug.print("eBPF program 'trace_execve' started!\n", .{});
    std.debug.print("Listening to /sys/kernel/tracing/trace_pipe...\n", .{});
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    var threaded: std.Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();
    while (true) {
        io.sleep(.fromSeconds(1), .awake) catch {};
    }
}
