const std = @import("std");
const http = @import("http.zig");

const Self = @This();

host: []const u8,
port: u16,
io: std.Io,

pub fn create(host: []const u8, port: u16, io: std.Io) Self {
    return .{ .host = host, .port = port, .io = io };
}

fn b64encode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const enc = std.base64.standard.Encoder;
    const size = enc.calcSize(input.len);
    const buf = try allocator.alloc(u8, size);
    _ = enc.encode(buf, input);
    return buf;
}

fn b64decode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const dec = std.base64.standard.Decoder;
    const size = try dec.calcSizeForSlice(input);
    const buf = try allocator.alloc(u8, size);
    try dec.decode(buf, input);
    return buf;
}

pub fn put(self: *Self, alloc: std.mem.Allocator, key: []const u8, value: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    const key_b64 = try b64encode(allocator, key);
    const val_b64 = try b64encode(allocator, value);

    const body = try std.fmt.allocPrint(allocator, "{{\"key\":\"{s}\",\"value\":\"{s}\"}}", .{ key_b64, val_b64 });

    _ = try http.request(allocator, self.io, self.host, self.port, "POST", "/v3/kv/put", body);
}

pub fn get(self: *Self, alloc: std.mem.Allocator, key: []const u8) !?[]const u8 {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    const key_b64 = try b64encode(allocator, key);

    const body = try std.fmt.allocPrint(allocator, "{{\"key\":\"{s}\"}}", .{key_b64});

    const resp = try http.request(allocator, self.io, self.host, self.port, "POST", "/v3/kv/range", body);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, resp, .{});

    const kvs = parsed.value.object.get("kvs") orelse return null;
    if (kvs.array.items.len == 0) return null;

    const kv = kvs.array.items[0];
    const val_b64 = kv.object.get("value") orelse return null;
    return try b64decode(allocator, val_b64.string);
}

pub fn getPrefix(self: *Self, alloc: std.mem.Allocator, prefix: []const u8) ![]AgentStatus {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const allocator = arena.allocator();
    const prefix_b64 = try b64encode(allocator, prefix);

    const body = try std.fmt.allocPrint(allocator, "{{\"key\":\"{s}\",\"range_end\":\"{s}\"}}", .{ prefix_b64, keyEnd(allocator, prefix_b64) catch unreachable });

    const resp = try http.request(allocator, self.io, self.host, self.port, "POST", "/v3/kv/range", body);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, resp, .{});

    const kvs = parsed.value.object.get("kvs") orelse return &.{};
    var result = try std.ArrayList(AgentStatus).initCapacity(allocator, kvs.array.items.len);

    for (kvs.array.items) |kv| {
        const key_b64 = kv.object.get("key") orelse continue;
        const val_b64 = kv.object.get("value") orelse continue;

        const key_bytes = try b64decode(allocator, key_b64.string);
        const val_bytes = try b64decode(allocator, val_b64.string);

        const hostname = key_bytes[prefix.len..];
        try result.append(allocator, .{
            .hostname = try allocator.dupe(u8, hostname),
            .status = try allocator.dupe(u8, val_bytes),
        });
    }

    return result.toOwnedSlice(allocator);
}

fn keyEnd(allocator: std.mem.Allocator, prefix_b64: []const u8) ![]u8 {
    const end = try allocator.dupe(u8, prefix_b64);
    for (end) |*c| {
        if (c.* != 0xFF) {
            c.* += 1;
            return end;
        }
        c.* = 0;
    }
    return end;
}

pub const AgentStatus = struct {
    hostname: []const u8,
    status: []const u8,
};

