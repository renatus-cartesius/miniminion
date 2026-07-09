const std = @import("std");
const cmd = @import("../modules/utils/cmd.zig");
const Self = @This();

pub const tag = "dnf_pkg";

name: []const u8 = "",
version: ?[]const u8 = null,
io: ?std.Io = null,
allocator: ?std.mem.Allocator = null,

pub fn create(name: []const u8, version: ?[]const u8) Self {
    return Self{ .name = name, .version = version };
}

pub fn parseJson(allocator: std.mem.Allocator, data: std.json.Value) !Self {
    _ = allocator;
    const name = data.object.get("name") orelse return error.MissingField;
    const version = if (data.object.get("version")) |v| v.string else null;
    return Self.create(name.string, version);
}

pub fn init(self: *Self, io: std.Io, allocator: std.mem.Allocator) !void {
    self.io = io;
    self.allocator = allocator;
}

pub fn apply(self: *Self) !bool {
    const io = self.io orelse return error.IoNotInitialized;
    const allocator = self.allocator orelse return error.AllocatorNotInitialized;

    if (self.version) |v| {
        const argv = [_][]const u8{ "rpm", "-q", self.name, "--queryformat", "%{VERSION}" };
        const res = try cmd.run(allocator, io, &argv);
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }
        if (res.term == .exited and res.term.exited == 0) {
            if (std.mem.eql(u8, std.mem.trim(u8, res.stdout, " \n\r"), v)) {
                return false;
            }
        }
    } else {
        const argv = [_][]const u8{ "rpm", "-q", self.name };
        const res = try cmd.run(allocator, io, &argv);
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }
        if (res.term == .exited and res.term.exited == 0) {
            return false;
        }
    }

    var argv = try std.ArrayList([]const u8).initCapacity(allocator, 3);
    defer argv.deinit(allocator);
    try argv.appendSlice(allocator, &[_][]const u8{ "dnf", "install", "-y" });

    if (self.version) |v| {
        const full = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ self.name, v });
        defer allocator.free(full);
        try argv.append(allocator, full);
    } else {
        try argv.append(allocator, self.name);
    }

    const res = try cmd.run(allocator, io, argv.items);
    defer {
        allocator.free(res.stdout);
        allocator.free(res.stderr);
    }
    if (res.term != .exited or res.term.exited != 0) {
        return error.PackageInstallFailed;
    }
    return true;
}