const std = @import("std");
const cmd = @import("../modules/utils/cmd.zig");
const Self = @This();

pub const tag = "sysctl";

content: []const u8 = "",
io: ?std.Io = null,
allocator: ?std.mem.Allocator = null,

pub fn create(content: []const u8) Self {
    return Self{ .content = content };
}

pub fn parseJson(allocator: std.mem.Allocator, data: std.json.Value) !Self {
    const params = data.object.get("params") orelse return error.MissingField;
    var buf = try std.ArrayList(u8).initCapacity(allocator, 512);
    var iter = params.object.iterator();
    while (iter.next()) |entry| {
        try buf.appendSlice(allocator, entry.key_ptr.*);
        try buf.appendSlice(allocator, " = ");
        try buf.appendSlice(allocator, entry.value_ptr.*.string);
        try buf.append(allocator, '\n');
    }
    return Self.create(try buf.toOwnedSlice(allocator));
}

pub fn init(self: *Self, io: std.Io, allocator: std.mem.Allocator) !void {
    self.io = io;
    self.allocator = allocator;
}

pub fn apply(self: *Self) !bool {
    const io = self.io orelse return error.IoNotInitialized;
    const allocator = self.allocator orelse return error.AllocatorNotInitialized;

    var changed = false;
    var lines = std.mem.splitScalar(u8, self.content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");
        if (trimmed.len == 0) continue;
        var parts = std.mem.splitScalar(u8, trimmed, '=');
        const key = std.mem.trim(u8, parts.first(), " ");
        const expected = std.mem.trim(u8, parts.rest(), " ");

        const argv = [_][]const u8{ "sysctl", "-n", key };
        const res = try cmd.run(allocator, io, &argv);
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }
        if (res.term == .exited and res.term.exited == 0) {
            const current = std.mem.trim(u8, res.stdout, " \n\r");
            if (std.mem.eql(u8, current, expected)) continue;
        }
        changed = true;
    }

    if (!changed) return false;

    {
        const argv = [_][]const u8{ "sh", "-c", try std.fmt.allocPrint(allocator, "cat > /etc/sysctl.d/99-miniminion.conf << 'EOF'\n{s}EOF", .{self.content}) };
        defer allocator.free(argv[2]);
        const res = try cmd.run(allocator, io, &argv);
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }
    }

    {
        const argv = [_][]const u8{ "sysctl", "--system" };
        const res = try cmd.run(allocator, io, &argv);
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }
    }

    return true;
}