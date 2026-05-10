const std = @import("std");

pub fn run(allocator: std.mem.Allocator, io: std.Io, argv: []const []const u8) !std.process.RunResult {
    const res = try std.process.run(allocator, io, .{
        .argv = argv,
    });

    return res;
}
