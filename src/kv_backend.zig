const std = @import("std");
const http = @import("http.zig");

controller_host: []const u8,
controller_port: u16,
io: std.Io,

pub fn create(host: []const u8, port: u16, io: std.Io) KvBackend {
    return .{ .controller_host = host, .controller_port = port, .io = io };
}

pub const KvBackend = struct {
    controller_host: []const u8,
    controller_port: u16,
    io: std.Io,

    pub fn get(self: KvBackend, alloc: std.mem.Allocator, key: []const u8) !?[]const u8 {
        const path = try std.fmt.allocPrint(alloc, "/kv/get?key={s}", .{key});
        defer alloc.free(path);
        const resp = http.request(alloc, self.io, self.controller_host, self.controller_port, "GET", path, "") catch |err| {
            std.debug.print("kv_backend: controller get failed: {}\n", .{err});
            return null;
        };
        if (resp.len == 0) {
            alloc.free(resp);
            return null;
        }
        return resp;
    }

    pub fn put(self: KvBackend, alloc: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        const body = try std.fmt.allocPrint(alloc, "{{\"key\":\"{s}\",\"value\":\"{s}\"}}", .{ key, value });
        defer alloc.free(body);
        _ = try http.request(alloc, self.io, self.controller_host, self.controller_port, "POST", "/kv/put", body);
    }
};