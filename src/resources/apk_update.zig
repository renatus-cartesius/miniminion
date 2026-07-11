const std = @import("std");
const cmd = @import("../modules/utils/cmd.zig");
const Self = @This();

pub const tag = "apk_update";

io: ?std.Io = null,
allocator: ?std.mem.Allocator = null,

pub fn create() Self {
    return Self{};
}

pub fn parseJson(allocator: std.mem.Allocator, data: std.json.Value) !Self {
    _ = allocator;
    _ = data;
    return Self.create();
}

pub fn init(self: *Self, io: std.Io, allocator: std.mem.Allocator) !void {
    self.io = io;
    self.allocator = allocator;
}

pub fn apply(self: *Self) !bool {
    const io = self.io orelse return error.IoNotInitialized;
    const allocator = self.allocator orelse return error.AllocatorNotInitialized;
    const argv = [_][]const u8{ "apk", "update" };
    const res = try cmd.run(allocator, io, &argv);
    defer {
        allocator.free(res.stdout);
        allocator.free(res.stderr);
    }
    if (res.term != .exited or res.term.exited != 0) {
        return error.CommandFailed;
    }
    return true;
}