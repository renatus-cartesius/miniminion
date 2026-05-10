const std = @import("std");
const c = @cImport({
    @cInclude("libjsonnet.h");
});
const resource = @import("resource.zig");
const dag = @import("dag.zig");

pub fn main(init: std.process.Init) !void {
    const print = std.debug.print;
    const io = init.io;

    const allocator = init.arena.allocator();

    const vm = c.jsonnet_make() orelse return error.JsonnetVmMakeError;
    defer c.jsonnet_destroy(vm);

    const file_path = "/minim.jsonnet";

    var file = try std.Io.Dir.openFile(std.Io.Dir.cwd(), io, "./minim.jsonnet", .{});
    defer file.close(io);
    const buf = try allocator.alloc(u8, 1024 * 1024);
    var reader = file.reader(io, buf);
    const content = try reader.interface.readAlloc(allocator, try file.length(io));

    var error_found: i32 = 0;
    // const result_ptr = c.jsonnet_evaluate_snippet_multt(vm, filename, input, &error_found);
    const result_ptr = c.jsonnet_evaluate_snippet(vm, file_path, content.ptr, &error_found);

    if (result_ptr) |ptr| {
        defer _ = c.jsonnet_realloc(vm, ptr, 0);
        const json_output = std.mem.span(ptr);

        if (error_found != 0) {
            print("Jsonnet Error: {s}\n", .{json_output});
            return error.JsonnetEvalError;
        }

        // print("Generated json:\n{s}\n", .{json_output});
        // const resources = try parseResourses(allocator, json_output);

        // std.debug.print("RES 1: {}", .{resources[0]});
        const resources = try resource.parseReources(init.arena, json_output);
        var rdag = try dag.DAG(resource.Resource).init(allocator);
        defer rdag.deinit();
        var rmap = std.StringHashMap(usize).init(allocator);
        defer rmap.deinit();

        // print("Parsed state:\n", .{});

        for (resources) |r| {
            try rmap.put(r.name, try rdag.addNode(r));

            // print("Resource {s}:\n", .{r.name});
            // switch (r.data) {
            //     .file => |f| print("\tfilepath: {s}, content: {s}\n", .{ f.path, f.content }),
            //     .package => |p| print("\tname: {s}, version: {s}\n", .{ p.name, p.version orelse "unset" }),
            // }
            //
            // for (r.deps) |d| {
            //     print("\t\tDependency: {s}\n", .{d});
            // }
        }

        for (resources) |r| {
            for (r.deps) |d| {
                try rdag.addEdge(rmap.get(r.name) orelse return resource.ResourceErrors.NotFoundResource, rmap.get(d) orelse return resource.ResourceErrors.NotFoundResource);
            }
        }

        const order = try rdag.topologicalSort(allocator);
        defer allocator.free(order);

        // print("\nState execution order: ", .{});
        // for (order) |i| {
        //     std.debug.print("{s} -> ", .{rdag.nodes.items[i].value.name});
        // }
        // std.debug.print("End.\n", .{});

        for (order) |i| {
            // try rdag.nodes.items[i].value.data.init(io, allocator);
            _ = try rdag.nodes.items[i].value.data.apply();
        }
    }
}
