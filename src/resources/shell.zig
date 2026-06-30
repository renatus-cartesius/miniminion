const std = @import("std");
const cmd = @import("../modules/utils/cmd.zig");
const Self = @This();

command: []const u8 = "",
io: ?std.Io = null,
allocator: ?std.mem.Allocator = null,

pub fn create(command: []const u8) Self {
    return Self{ .command = command };
}

pub fn init(self: *Self, io: std.Io, allocator: std.mem.Allocator) !void {
    self.io = io;
    self.allocator = allocator;
}

pub fn apply(self: *Self) !bool {
    const io = self.io orelse return error.IoNotInitialized;
    const allocator = self.allocator orelse return error.AllocatorNotInitialized;

    const argv = [_][]const u8{ "sh", "-c", self.command };
    const result = try cmd.run(allocator, io, &argv);
    defer {
        allocator.free(result.stderr);
        allocator.free(result.stdout);
    }

    if (result.term.exited == 0) {
        std.debug.print("shell: command CHANGED\n", .{});
        return true;
    }

    std.debug.print("shell: command FAILED, exit code: {}\n", .{result.term.exited});
    return true;
}