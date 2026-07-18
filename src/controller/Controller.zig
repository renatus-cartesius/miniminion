const std = @import("std");

const Self = @This();

allocator: std.mem.Allocator,
io: std.Io,

pub fn create(init: std.process.Init) Self {
    return .{ .allocator = init.arena.allocator(), .io = init.io };
}

pub fn run(self: *Self, manifest_path: []const u8, port: u16) !void {
    const file = try std.Io.Dir.openFile(std.Io.Dir.cwd(), self.io, manifest_path, .{});
    defer file.close(self.io);
    const read_buf = try self.allocator.alloc(u8, 1024 * 1024);
    defer self.allocator.free(read_buf);
    var file_reader = file.reader(self.io, read_buf);
    const manifest = try file_reader.interface.readAlloc(self.allocator, try file.length(self.io));
    defer self.allocator.free(manifest);

    const address = try std.Io.net.IpAddress.parse("0.0.0.0", port);
    var server = try std.Io.net.IpAddress.listen(&address, self.io, .{ .reuse_address = true, .mode = .stream });
    defer server.deinit(self.io);

    std.debug.print("controller: listening on {d}, serving {s}\n", .{ port, manifest_path });

    while (true) {
        const conn = try server.accept(self.io);
        defer conn.close(self.io);
        var write_buf: [65536]u8 = undefined;
        var writer = std.Io.net.Stream.writer(conn, self.io, &write_buf);
        try writer.interface.writeAll(manifest);
        try writer.interface.flush();
        std.debug.print("controller: sent manifest\n", .{});
    }
}