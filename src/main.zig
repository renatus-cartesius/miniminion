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

// pub fn parseResourses(allocator: std.mem.Allocator, json_input: []const u8) !std.StringArrayHashMap(Resource) {
//     const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_input, .{});
//     defer parsed.deinit();
//
//     var resources = std.StringArrayHashMap(Resource).init(allocator);
//     errdefer {
//         resources.deinit();
//     }
//
//     const root_obj = parsed.Value.object;
//
//     var iter = root_obj.iterator();
//     while (iter.next()) |entry| {
//         const key = entry.key_ptr.*;
//         const val = entry.value_ptr.object;
//
//         const res_type = val.get("type").?.string;
//
//         if (std.mem.eql(u8, res_type, "file")) {
//             const content = try allocator.dupe(u8, val.get("content").?.string);
//             try resources.put(try allocator.dupe(u8, key), .{ .file = .{ .content = content } });
//         } else if (std.mem.eql(u8, res_type, "package")) {
//             const name = try .allocator.dupe(u8, val.get("name").?.string);
//             try resources.put(try allocator.dupe(u8, key), .{ .package = .{ .name = name } });
//         }
//     }
//
//     return resources;
// }
