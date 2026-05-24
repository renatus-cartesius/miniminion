const std = @import("std");
const resource = @import("resource.zig");
const dag = @import("dag.zig");
const manifest = @import("manifest.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const allocator = init.arena.allocator();

    const file_path = "./minim.jsonnet";

    const manifest_data = try manifest.Manifest.load(allocator, io, file_path);
    defer allocator.free(manifest_data.json_output);

    std.debug.print("Generated JSON:\n{s}\n", .{manifest_data.json_output});

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
