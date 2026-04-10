const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;

const c = @cImport({
    @cInclude("bpf/libbpf.h");
});

pub fn main() !void {
    const bpf_obj_path = "src/bpf_progs/compiled/trace_bpf.o";
    // const bpf_obj_path = "../ebpf-test/zig/hello.bpf.o";

    std.debug.print("=== eBPF Loader ===\n", .{});
    std.debug.print("Attempting to load: {s}\n", .{bpf_obj_path});

    const obj = c.bpf_object__open(bpf_obj_path) orelse {
        std.debug.print("Failed to open BPF object\n", .{});
        return error.BpfOpenFailed;
    };
    defer c.bpf_object__close(obj);

    if (c.bpf_object__load(obj) < 0) {
        std.debug.print("Error loading BPF into kernel\n", .{});
        std.debug.print("Try: ulimit -l unlimited\n", .{});
        return error.BpfLoadFailed;
    }

    std.debug.print("BPF object loaded successfully!\n", .{});

    // const prog = c.bpf_object__find_program_by_name(obj, "hello_world") orelse {
    //     std.debug.print("Failed to find program 'trace_execve'\n", .{});
    //     return error.ProgramNotFound;
    // };
    //
    // std.debug.print("Program 'trace_execve' found, attaching...\n", .{});
    //
    // const link = c.bpf_program__attach(prog) orelse {
    //     std.debug.print("Error attaching program\n", .{});
    //     return error.BpfAttachFailed;
    // };
    // defer _ = c.bpf_link__destroy(link);
    //
    // std.debug.print("eBPF program 'trace_execve' attached successfully!\n", .{});
    // std.debug.print("Listening to /sys/kernel/tracing/trace_pipe...\n", .{});
    // std.debug.print("Trigger execve by running: bash -c 'echo test' &\n", .{});
    // std.debug.print("Press Ctrl+C to stop\n\n", .{});

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    var threaded: std.Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // Main loop - print messages periodically
    var counter: u32 = 0;
    while (true) {
        io.sleep(.fromSeconds(3), .awake) catch {};
        counter += 1;
        if (counter % 2 == 0) {
            std.debug.print("Still running... ({}s)\n", .{counter * 3});
        }
    }
}
