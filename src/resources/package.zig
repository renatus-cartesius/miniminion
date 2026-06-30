const std = @import("std");
const package = @import("../modules/package.zig");
const Self = @This();

name: []const u8 = "",
version: ?[]const u8 = null,
mgr: ?package.Manager = null,
io: ?std.Io = null,
allocator: ?std.mem.Allocator = null,

pub fn create(name: []const u8, version: ?[]const u8) Self {
    return Self{ .name = name, .version = version };
}

pub fn init(self: *Self, io: std.Io, allocator: std.mem.Allocator) !void {
    self.allocator = allocator;
    self.io = io;
    self.mgr = package.Manager.init(allocator);
}

pub fn apply(self: *Self) !bool {
    if (try self.mgr.?.checkVersion(self.io.?, self.name, self.version)) {
        std.debug.print("package: {s}={s} : OK\n", .{ self.name, self.version orelse "latest" });
        return false;
    } else {
        try self.mgr.?.install(
            self.io.?,
            self.name,
            self.version,
        );
        std.debug.print("package: {s} CHANGED installed\n", .{self.name});
        return true;
    }
}