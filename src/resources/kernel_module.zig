const std = @import("std");
const cmd = @import("../modules/utils/cmd.zig");
const Self = @This();

pub const tag = "kernel_module";

modules: [][]const u8 = &.{},
io: ?std.Io = null,
allocator: ?std.mem.Allocator = null,

pub fn create(modules: [][]const u8) Self {
    return Self{ .modules = modules };
}

pub fn parseJson(allocator: std.mem.Allocator, data: std.json.Value) !Self {
    const modules_val = data.object.get("modules") orelse return error.MissingField;
    var modules = try std.ArrayList([]const u8).initCapacity(allocator, modules_val.array.items.len);
    for (modules_val.array.items) |item| {
        modules.appendAssumeCapacity(item.string);
    }
    return Self.create(try modules.toOwnedSlice(allocator));
}

pub fn init(self: *Self, io: std.Io, allocator: std.mem.Allocator) !void {
    self.io = io;
    self.allocator = allocator;
}

pub fn apply(self: *Self) !bool {
    const io = self.io orelse return error.IoNotInitialized;
    const allocator = self.allocator orelse return error.AllocatorNotInitialized;
    var changed = false;

    for (self.modules) |mod| {
        const argv_check = [_][]const u8{ "sh", "-c", try std.fmt.allocPrint(allocator, "grep -q '^{s} ' /proc/modules", .{mod}) };
        defer allocator.free(argv_check[2]);
        const check = try cmd.run(allocator, io, &argv_check);
        defer {
            allocator.free(check.stdout);
            allocator.free(check.stderr);
        }
        if (check.term == .exited and check.term.exited == 0) continue;

        const argv_mod = [_][]const u8{ "modprobe", mod };
        const res = try cmd.run(allocator, io, &argv_mod);
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }
        changed = true;
    }

    return changed;
}