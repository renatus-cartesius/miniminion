const std = @import("std");
const cmd = @import("../modules/utils/cmd.zig");
const Self = @This();

pub const tag = "apk_pkg";

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

    const argv_check = [_][]const u8{ "apk", "info", "-e", self.name };
    const check = try cmd.run(allocator, io, &argv_check);
    defer {
        allocator.free(check.stdout);
        allocator.free(check.stderr);
    }
    const installed = check.term == .exited and check.term.exited == 0;
    if (installed) {
        if (self.version) |v| {
            const argv_v = [_][]const u8{ "apk", "list", "-I", "-e", self.name };
            const res_v = try cmd.run(allocator, io, &argv_v);
            defer {
                allocator.free(res_v.stdout);
                allocator.free(res_v.stderr);
            }
            const trimmed = std.mem.trim(u8, res_v.stdout, " \n\r");
            if (std.mem.lastIndexOfScalar(u8, trimmed, '-')) |dash| {
                const ver_part = trimmed[dash + 1 ..];
                if (std.mem.indexOfScalar(u8, ver_part, '-')) |sub| {
                    if (std.mem.eql(u8, ver_part[0..sub], v)) return false;
                } else if (std.mem.eql(u8, ver_part, v)) {
                    return false;
                }
            }
        } else {
            return false;
        }
    }

    const argv_install = [_][]const u8{ "apk", "add", self.name };
    const res = try cmd.run(allocator, io, &argv_install);
    defer {
        allocator.free(res.stdout);
        allocator.free(res.stderr);
    }
    if (res.term != .exited or res.term.exited != 0) {
        const stderr_trimmed = std.mem.trim(u8, res.stderr, "\n");
        if (stderr_trimmed.len > 0) {
            std.debug.print("  stderr: {s}\n", .{stderr_trimmed});
        }
        return error.PackageInstallFailed;
    }
    return true;
}