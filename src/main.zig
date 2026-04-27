const std = @import("std");
const c = @cImport({
    @cInclude("libjsonnet.h");
});
const resource = @import("resource.zig");

pub fn main() !void {
    // const allocator = std.heap.page_allocator;

    const vm = c.jsonnet_make() orelse return error.JsonnetVmMakeError;
    defer c.jsonnet_destroy(vm);

    // miniminion example resources manifest
    const input =
        \\local Resource(type, name, args={}) = {
        \\  type: type,
        \\  name: name,
        \\} + args;
        \\{
        \\  config_file: Resource("file", "myconfig", {"content": "foobar"}),
        \\  some_pkg: Resource("package", "mypackage", {"name": "vim", version: "1.2.3"})
        \\}
    ;
    const filename = "example.jsonnet";

    var error_found: i32 = 0;
    // const result_ptr = c.jsonnet_evaluate_snippet_multt(vm, filename, input, &error_found);
    const result_ptr = c.jsonnet_evaluate_snippet(vm, filename, input, &error_found);

    if (error_found != 0) {
        std.debug.print("Jsonnet Error: {}\n", .{error_found});
        return error.JsonnetEvalError;
    }

    if (result_ptr) |ptr| {
        defer _ = c.jsonnet_realloc(vm, ptr, 0);
        const json_output = std.mem.span(ptr);
        std.debug.print("Generated json:\n{s}\n", .{json_output});
        // const resources = try parseResourses(allocator, json_output);

        // std.debug.print("RES 1: {}", .{resources[0]});
    }
}
