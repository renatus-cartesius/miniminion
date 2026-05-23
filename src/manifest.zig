const std = @import("std");
const c = @cImport({
    @cInclude("libjsonnet.h");
});

pub const Manifest = struct {
    json_output: []const u8,

    pub fn load(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8) !Manifest {
        const vm = c.jsonnet_make() orelse return error.JsonnetVmMakeError;
        defer c.jsonnet_destroy(vm);

        var file = try std.Io.Dir.openFile(std.Io.Dir.cwd(), io, file_path, .{});
        defer file.close(io);
        const buf = try allocator.alloc(u8, 1024 * 1024);
        defer allocator.free(buf);
        var reader = file.reader(io, buf);
        const content = try reader.interface.readAlloc(allocator, try file.length(io));

        var error_found: i32 = 0;
        const result_ptr = c.jsonnet_evaluate_snippet(vm, &file_path[0], &content[0], &error_found);

        if (result_ptr) |ptr| {
            defer _ = c.jsonnet_realloc(vm, ptr, 0);
            const json_output = std.mem.span(ptr);

            if (error_found != 0) {
                return error.JsonnetEvalError;
            }

            return Manifest{ .json_output = json_output };
        }

        return error.JsonnetEvalError;
    }
};
