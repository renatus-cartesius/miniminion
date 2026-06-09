const std = @import("std");
const resource = @import("resource.zig");
const dag = @import("dag.zig");
const manifest = @import("manifest.zig");
const c = @cImport({
    @cInclude("bpf/libbpf.h");
});

pub fn main(init: std.process.Init) !void {
    _ = init;

    const prog_pin_path = "/sys/fs/bpf/foobar_bpf_prog";
    const prog_link_pin_path = "/sys/fs/bpf/foobar_bpf_prog_link";
    const prog_name = "trace_foobar_change";

    std.debug.print("Removing program pin: {s}\n", .{prog_pin_path});
    _ = std.os.linux.unlink(prog_pin_path ++ "/" ++ prog_name);
    std.debug.print("Removing link pin: {s}\n", .{prog_link_pin_path});
    _ = std.os.linux.unlink(prog_link_pin_path);

    const bpf_bytecode: []const u8 = @embedFile("./bpf_sensors/obj/file.o");
    std.debug.print("Openning bpf bytecode\n", .{});
    const obj = c.bpf_object__open_mem(
        bpf_bytecode.ptr,
        bpf_bytecode.len,
        null,
    );
    defer c.bpf_object__close(obj);

    std.debug.print("Loading bpf prog\n", .{});
    if (c.bpf_object__load(obj) != 0) {
        return error.BpfLoadFailed;
    }
    std.debug.print("Bpf prog loaded\n", .{});

    const prog = c.bpf_object__find_program_by_name(obj, prog_name) orelse return error.BpfProgNotFound;
    std.debug.print("Pinning bpf object\n", .{});
    _ = c.bpf_object__pin(obj, prog_pin_path);
    const fd = c.bpf_program__fd(prog);
    std.debug.print("BPF sensor file loaded, fd={d}\n\n", .{fd});

    std.debug.print("Attaching bpf prog to event\n", .{});
    const link = c.bpf_program__attach(prog) orelse {
        return error.BpfCreateLinkFailed;
    };
    std.debug.print("Pinning prog link\n", .{});
    if (c.bpf_link__pin(link, prog_link_pin_path) != 0) {
        return error.BpfPinLinkFailed;
    }
    errdefer _ = c.bpf_link__destroy(link);
}

// Temp main

pub fn dummy(init: std.process.Init) !void {
    const io = init.io;

    const allocator = init.arena.allocator();

    const file_path = "./minim.jsonnet";

    const manifest_data = try manifest.Manifest.load(allocator, io, file_path);
    defer allocator.free(manifest_data.json_output);

    // std.debug.print("Generated JSON:\n{s}\n", .{manifest_data.json_output});

    const resources = try resource.parseReources(init.arena, manifest_data.json_output);
    std.debug.print("JSON parsed successfully, resources count: {d}\n", .{resources.len});
    var rdag = try dag.DAG(resource.Resource).init(allocator);
    defer rdag.deinit();
    var rmap = std.StringHashMap(usize).init(allocator);
    defer rmap.deinit();

    for (resources) |r| {
        try rmap.put(r.name, try rdag.addNode(r));
    }

    for (resources) |r| {
        for (r.deps) |d| {
            try rdag.addEdge(rmap.get(r.name) orelse return resource.ResourceErrors.NotFoundResource, rmap.get(d) orelse return resource.ResourceErrors.NotFoundResource);
        }
    }

    const order = try rdag.topologicalSort(allocator);
    defer allocator.free(order);

    for (order) |i| {
        try rdag.nodes.items[i].value.data.init(init.io, allocator);
        _ = try rdag.nodes.items[i].value.data.apply();
    }
}
