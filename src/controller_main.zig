const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    const manifest_path = if (args.len > 1) args[1] else "minim.jsonnet";
    const port: u16 = if (args.len > 2) try std.fmt.parseInt(u16, args[2], 10) else 9876;

    var file = try std.Io.Dir.openFile(std.Io.Dir.cwd(), io, manifest_path, .{});
    defer file.close(io);
    const read_buf = try allocator.alloc(u8, 1024 * 1024);
    defer allocator.free(read_buf);
    var file_reader = file.reader(io, read_buf);
    const manifest = try file_reader.interface.readAlloc(allocator, try file.length(io));
    defer allocator.free(manifest);

    const address = try std.Io.net.IpAddress.parse("0.0.0.0", port);
    var server = try std.Io.net.IpAddress.listen(&address, io, .{ .reuse_address = true, .mode = .stream });
    defer server.deinit(io);

    std.debug.print("controller: listening on {d}, serving {s}\n", .{ port, manifest_path });

    while (true) {
        const conn = try server.accept(io);
        defer conn.close(io);
        var write_buf: [65536]u8 = undefined;
        var writer = std.Io.net.Stream.writer(conn, io, &write_buf);
        try writer.interface.writeAll(manifest);
        try writer.interface.flush();
        std.debug.print("controller: sent manifest\n", .{});
    }
}

