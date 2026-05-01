const std = @import("std");
const c = @cImport({
    @cInclude("libjsonnet.h");
});
const resource = @import("resource.zig");
const dag = @import("dag.zig");

pub fn main() !void {
    const print = std.debug.print;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const vm = c.jsonnet_make() orelse return error.JsonnetVmMakeError;
    defer c.jsonnet_destroy(vm);

    const filename = "example.jsonnet";

    var error_found: i32 = 0;
    // const result_ptr = c.jsonnet_evaluate_snippet_multt(vm, filename, input, &error_found);
    const result_ptr = c.jsonnet_evaluate_snippet(vm, filename, input, &error_found);

    if (error_found != 0) {
        print("Jsonnet Error: {}\n", .{error_found});
        return error.JsonnetEvalError;
    }

    if (result_ptr) |ptr| {
        defer _ = c.jsonnet_realloc(vm, ptr, 0);
        const json_output = std.mem.span(ptr);
        print("Generated json:\n{s}\n", .{json_output});
        // const resources = try parseResourses(allocator, json_output);

        // std.debug.print("RES 1: {}", .{resources[0]});
        const resources = try resource.parseReources(&arena, json_output);
        var rdag = try dag.DAG(resource.Resource).init(allocator);
        defer rdag.deinit();
        var rmap = std.StringHashMap(usize).init(allocator);
        defer rmap.deinit();

        print("Parsed state:\n", .{});

        for (resources) |r| {
            try rmap.put(r.name, try rdag.addNode(r));

            print("Resource {s}:\n", .{r.name});
            switch (r.data) {
                .file => |f| print("\tfilepath: {s}, content: {s}\n", .{ f.path, f.content }),
                .package => |p| print("\tname: {s}, version: {s}\n", .{ p.name, p.version orelse "unset" }),
            }

            for (r.deps) |d| {
                print("\t\tDependency: {s}\n", .{d});
            }
        }
    }
}
