const std = @import("std");

pub const RuntimeContext = struct {
    allocator: std.mem.Allocator,
    outputs: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) RuntimeContext {
        return .{
            .allocator = allocator,
            .outputs = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn store(self: *RuntimeContext, name: []const u8, value: []const u8) !void {
        try self.outputs.put(name, value);
    }

    pub fn get(self: *RuntimeContext, name: []const u8) ?[]const u8 {
        return self.outputs.get(name);
    }

    pub fn has(self: *RuntimeContext, name: []const u8) bool {
        return self.outputs.contains(name);
    }

    pub fn deinit(self: *RuntimeContext) void {
        self.outputs.deinit();
    }
};