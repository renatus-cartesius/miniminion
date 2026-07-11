const std = @import("std");
const cmd = @import("../modules/utils/cmd.zig");
const Self = @This();

pub const tag = "apt_repo";

key_url: []const u8 = "",
key_path: []const u8 = "",
source: []const u8 = "",
source_path: []const u8 = "",
io: ?std.Io = null,
allocator: ?std.mem.Allocator = null,

pub fn create(key_url: []const u8, key_path: []const u8, source: []const u8, source_path: []const u8) Self {
    return Self{ .key_url = key_url, .key_path = key_path, .source = source, .source_path = source_path };
}

pub fn parseJson(allocator: std.mem.Allocator, data: std.json.Value) !Self {
    _ = allocator;
    const key_url = data.object.get("key_url") orelse return error.MissingField;
    const key_path = data.object.get("key_path") orelse return error.MissingField;
    const source = data.object.get("source") orelse return error.MissingField;
    const source_path = data.object.get("source_path") orelse return error.MissingField;
    return Self.create(key_url.string, key_path.string, source.string, source_path.string);
}

pub fn init(self: *Self, io: std.Io, allocator: std.mem.Allocator) !void {
    self.io = io;
    self.allocator = allocator;
}

pub fn apply(self: *Self) !bool {
    const io = self.io orelse return error.IoNotInitialized;
    const allocator = self.allocator orelse return error.AllocatorNotInitialized;

    {
        const argv = [_][]const u8{ "test", "-f", self.source_path };
        const res = try cmd.run(allocator, io, &argv);
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }
        if (res.term == .exited and res.term.exited == 0) {
            return false;
        }
    }

    {
        var argv = try std.ArrayList([]const u8).initCapacity(allocator, 4);
        defer argv.deinit(allocator);
        try argv.appendSlice(allocator, &[_][]const u8{ "curl", "-fsSL", self.key_url, "-o" });
        try argv.append(allocator, self.key_path);
        const res = try cmd.run(allocator, io, argv.items);
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }
    }

    {
        var argv = try std.ArrayList([]const u8).initCapacity(allocator, 4);
        defer argv.deinit(allocator);
        try argv.appendSlice(allocator, &[_][]const u8{ "sh", "-c", try std.fmt.allocPrint(allocator, "echo '{s}' > {s}", .{ self.source, self.source_path }) });
        defer allocator.free(argv.items[2]);
        const res = try cmd.run(allocator, io, argv.items);
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }
    }

    return true;
}