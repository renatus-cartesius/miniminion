const std = @import("std");
const manifest = @import("manifest.zig");
const resource = @import("resource.zig");
const dag = @import("dag.zig");

const Self = @This();

pub fn run(self: *Self, init: std.process.Init, manifest_path: []const u8) !void {
    _ = self;

    const io = init.io;
    const allocator = init.arena.allocator();
    const file_path = manifest_path;

    const manifest_data = try manifest.Manifest.load(allocator, io, file_path);
    defer allocator.free(manifest_data.json_output);

    const resources = try resource.parseReources(init.arena, manifest_data.json_output);
    std.debug.print("state: parsed {d} resources\n", .{resources.len});
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

    var ok_count: usize = 0;
    var changed_count: usize = 0;
    var failed_count: usize = 0;

    for (order) |i| {
        const node = &rdag.nodes.items[i];
        const name = node.value.name;
        const type_name = node.value.data.typeName();

        try node.value.data.init(init.io, allocator);

        var ts_start: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(.MONOTONIC, &ts_start);

        const result = node.value.data.apply();

        var ts_end: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(.MONOTONIC, &ts_end);

        const elapsed_ns = (@as(i128, ts_end.sec) - @as(i128, ts_start.sec)) * std.time.ns_per_s + (@as(i128, ts_end.nsec) - @as(i128, ts_start.nsec));
        const elapsed_ms: f64 = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, std.time.ns_per_ms);

        if (result) |changed| {
            if (changed) {
                std.debug.print("  {s:>7}  {s:<25}  {s:<8}  {d:>6.0}ms\n", .{ "CHANGED", name, type_name, elapsed_ms });
                changed_count += 1;
            } else {
                std.debug.print("  {s:>7}  {s:<25}  {s:<8}\n", .{ "OK", name, type_name });
                ok_count += 1;
            }
        } else |_| {
            std.debug.print("  {s:>7}  {s:<25}  {s:<8}  {d:>6.0}ms\n", .{ "FAILED", name, type_name, elapsed_ms });
            failed_count += 1;
        }
    }

    const total = ok_count + changed_count + failed_count;
    std.debug.print("\nresult: {d}/{d} ok, {d} changed, {d} failed\n", .{ ok_count, total, changed_count, failed_count });
}