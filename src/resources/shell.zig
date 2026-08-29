const std = @import("std");
const cmd = @import("../modules/utils/cmd.zig");
const Self = @This();

pub const tag = "shell";

command: []const u8 = "",
io: ?std.Io = null,
allocator: ?std.mem.Allocator = null,
stdout: []const u8 = "",

pub fn create(command: []const u8) Self {
    return Self{ .command = command };
}

pub fn parseJson(allocator: std.mem.Allocator, data: std.json.Value) !Self {
    _ = allocator;
    const command = data.object.get("command") orelse return error.MissingField;
    return Self.create(command.string);
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
    errdefer {
        allocator.free(result.stderr);
        allocator.free(result.stdout);
    }

    if (result.term == .exited and result.term.exited == 0) {
        self.stdout = try allocator.dupe(u8, std.mem.trimEnd(u8, result.stdout, "\n\r"));
        allocator.free(result.stderr);
        return true;
    }

    if (result.term == .exited) {
        const exit_code = result.term.exited;
        const stderr_trimmed = std.mem.trim(u8, result.stderr, "\n");
        if (stderr_trimmed.len > 0) {
            std.debug.print("  stderr: {s}\n", .{stderr_trimmed});
        }
        std.debug.print("  exit code: {}\n", .{exit_code});
    }
    allocator.free(result.stdout);
    allocator.free(result.stderr);
    return error.ShellCommandFailed;
}

pub fn getOutput(self: *Self) ?[]const u8 {
    if (self.stdout.len > 0) return self.stdout;
    return null;
}