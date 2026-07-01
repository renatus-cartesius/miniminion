const std = @import("std");
const Self = @This();

path: []const u8 = "",
content: []const u8 = "",
mode: u32 = 0o655,
io: ?std.Io = null,
allocator: ?std.mem.Allocator = null,

pub fn create(path: []const u8, content: []const u8, mode: u32) Self {
    return Self{ .path = path, .content = content, .mode = mode };
}

pub fn init(self: *Self, io: std.Io, allocator: std.mem.Allocator) !void {
    self.io = io;
    self.allocator = allocator;
}

pub fn apply(self: *Self) !bool {
    const io = self.io orelse return error.IoNotInitialized;
    const allocator = self.allocator orelse return error.AllocatorNotInitialized;
    const open_result = std.Io.Dir.openFile(.cwd(), io, self.path, .{ .mode = .read_write });
    if (open_result) |file| {
        const buf = try allocator.alloc(u8, 1024 * 1024);
        defer allocator.free(buf);
        var reader = file.reader(io, buf);
        const content = try reader.interface.readAlloc(allocator, try file.length(io));

        const file_stat = try std.Io.Dir.statFile(.cwd(), io, self.path, .{});
        const expected_perms = std.Io.File.Permissions.fromMode(self.mode);
        var permissions_updated = false;

        const current_mode_bits = @intFromEnum(file_stat.permissions) & 0o777;
        const expected_mode_bits = @intFromEnum(expected_perms) & 0o777;

        if (current_mode_bits != expected_mode_bits) {
            try std.Io.Dir.setFilePermissions(.cwd(), io, self.path, expected_perms, .{});
            permissions_updated = true;
        }

        if (std.mem.eql(u8, content, self.content)) {
            file.close(io);
            return permissions_updated;
        }

        file.close(io);

        const options: std.Io.Dir.CreateFileOptions = .{ .read = true, .truncate = true, .permissions = std.Io.File.Permissions.fromMode(self.mode) };
        var new_file = try std.Io.Dir.createFile(.cwd(), io, self.path, options);

        var writer = new_file.writer(io, buf);
        _ = try writer.interface.write(self.content);
        _ = try writer.flush();

        new_file.close(io);
        return true;
    } else |err| {
        if (err == error.FileNotFound) {
            const perms = std.Io.File.Permissions.fromMode(self.mode);
            const options: std.Io.Dir.CreateFileOptions = .{ .read = true, .truncate = true, .permissions = perms };
            var new_file = try std.Io.Dir.createFile(.cwd(), io, self.path, options);

            const buf = try allocator.alloc(u8, 1024 * 1024);
            defer allocator.free(buf);
            var writer = new_file.writer(io, buf);
            _ = try writer.interface.write(self.content);
            _ = try writer.flush();

            new_file.close(io);
            return true;
        } else {
            return err;
        }
    }
}