const std = @import("std");
const state_manager = @import("../state_manager.zig");

const Self = @This();

process_init: std.process.Init,

pub fn create(init: std.process.Init) Self {
    return .{ .process_init = init };
}

pub fn run(self: *Self, manifest_path: []const u8) !void {
    var sm = state_manager{};
    try sm.run(self.process_init, manifest_path);
}

pub fn runFromController(self: *Self, host: []const u8, port: u16) !void {
    const io = self.process_init.io;
    const allocator = self.process_init.arena.allocator();

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

    try self.run(tmp_path);
}