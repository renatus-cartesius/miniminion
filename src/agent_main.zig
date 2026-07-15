const std = @import("std");
const state_manager = @import("state_manager.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    if (args.len > 2 and std.mem.eql(u8, args[1], "--controller")) {
        const host_port = args[2];
        const colon = std.mem.indexOfScalar(u8, host_port, ':') orelse return error.InvalidHostPort;
        const host = host_port[0..colon];
        const port = try std.fmt.parseInt(u16, host_port[colon + 1 ..], 10);

        std.debug.print("agent: fetching manifest from {s}:{d}\n", .{ host, port });

        const address = try std.Io.net.IpAddress.parse(host, port);
        const stream = try std.Io.net.IpAddress.connect(&address, io, .{ .mode = .stream });
        defer stream.close(io);

        var read_buf: [65536]u8 = undefined;
        var reader = std.Io.net.Stream.reader(stream, io, &read_buf);
        const manifest = try reader.interface.allocRemaining(allocator, .unlimited);
        defer allocator.free(manifest);

        const tmp_path = "/tmp/minim_manifest.jsonnet";
        const options: std.Io.Dir.CreateFileOptions = .{ .read = true, .truncate = true };
        var tmp_file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), io, tmp_path, options);
        defer tmp_file.close(io);
        const tmp_buf = try allocator.alloc(u8, 65536);
        defer allocator.free(tmp_buf);
        var tmp_writer = tmp_file.writer(io, tmp_buf);
        try tmp_writer.interface.writeAll(manifest);
        try tmp_writer.interface.flush();

        var sm = state_manager{};
        try sm.run(init, tmp_path);
    } else {
        const manifest_path = if (args.len > 1) args[1] else "minim.jsonnet";
        var sm = state_manager{};
        try sm.run(init, manifest_path);
    }
}