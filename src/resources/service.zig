const std = @import("std");
const cmd = @import("../modules/utils/cmd.zig");
const Self = @This();

pub const tag = "service";

name: []const u8 = "",
state: []const u8 = "running",
enabled: bool = true,
io: ?std.Io = null,
allocator: ?std.mem.Allocator = null,

pub fn create(name: []const u8, state: []const u8, enabled: bool) Self {
    return Self{ .name = name, .state = state, .enabled = enabled };
}

pub fn parseJson(allocator: std.mem.Allocator, data: std.json.Value) !Self {
    _ = allocator;
    const name = data.object.get("name") orelse return error.MissingField;
    const state = if (data.object.get("state")) |s| s.string else "running";
    const enabled = if (data.object.get("enabled")) |e| e.bool else true;
    return Self.create(name.string, state, enabled);
}

pub fn init(self: *Self, io: std.Io, allocator: std.mem.Allocator) !void {
    self.io = io;
    self.allocator = allocator;
}

fn systemctl(self: *Self, argv_extra: []const []const u8) !void {
    const io = self.io orelse return error.IoNotInitialized;
    const allocator = self.allocator orelse return error.AllocatorNotInitialized;
    var argv = try std.ArrayList([]const u8).initCapacity(allocator, argv_extra.len + 2);
    defer argv.deinit(allocator);
    try argv.append(allocator, "systemctl");
    try argv.appendSlice(allocator, argv_extra);
    try argv.append(allocator, self.name);
    const res = try cmd.run(allocator, io, argv.items);
    defer {
        allocator.free(res.stdout);
        allocator.free(res.stderr);
    }
}

fn isEnabled(self: *Self) !bool {
    const io = self.io orelse return error.IoNotInitialized;
    const allocator = self.allocator orelse return error.AllocatorNotInitialized;
    const argv = [_][]const u8{ "systemctl", "is-enabled", self.name };
    const res = try cmd.run(allocator, io, &argv);
    defer {
        allocator.free(res.stdout);
        allocator.free(res.stderr);
    }
    return res.term == .exited and res.term.exited == 0 and std.mem.eql(u8, std.mem.trim(u8, res.stdout, " \n\r"), "enabled");
}

fn isActive(self: *Self) !bool {
    const io = self.io orelse return error.IoNotInitialized;
    const allocator = self.allocator orelse return error.AllocatorNotInitialized;
    const argv = [_][]const u8{ "systemctl", "is-active", self.name };
    const res = try cmd.run(allocator, io, &argv);
    defer {
        allocator.free(res.stdout);
        allocator.free(res.stderr);
    }
    return res.term == .exited and res.term.exited == 0 and std.mem.eql(u8, std.mem.trim(u8, res.stdout, " \n\r"), "active");
}

pub fn apply(self: *Self) !bool {
    var changed = false;

    try self.systemctl(&.{ "daemon-reload" });

    const enabled = try self.isEnabled();
    if (self.enabled and !enabled) {
        try self.systemctl(&.{ "enable" });
        changed = true;
    } else if (!self.enabled and enabled) {
        try self.systemctl(&.{ "disable" });
        changed = true;
    }

    const active = try self.isActive();
    if (std.mem.eql(u8, self.state, "running") and !active) {
        try self.systemctl(&.{ "start" });
        changed = true;
    } else if (std.mem.eql(u8, self.state, "stopped") and active) {
        try self.systemctl(&.{ "stop" });
        changed = true;
    }

    return changed;
}