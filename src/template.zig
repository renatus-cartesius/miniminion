const std = @import("std");
const context = @import("context.zig");
const kv_backend = @import("kv_backend.zig");

const ResolveError = error{
    TemplateSyntaxError,
    ResourceNotFound,
    GlobalKeyNotFound,
    JsonPathNotFound,
    JsonPathNotNavigable,
    JsonPathNonStringLeaf,
};

pub fn resolve(allocator: std.mem.Allocator, input: []const u8, ctx: *context.RuntimeContext, kv: kv_backend.KvBackend) ![]const u8 {
    const start_marker = "{{";
    const end_marker = "}}";

    var result = try allocator.dupe(u8, input);
    errdefer allocator.free(result);

    var search_pos: usize = 0;
    while (search_pos < result.len) {
        const start_pos = std.mem.indexOf(u8, result[search_pos..], start_marker) orelse break;
        const abs_start = search_pos + start_pos;
        const after_start = abs_start + start_marker.len;
        const end_pos = std.mem.indexOf(u8, result[after_start..], end_marker) orelse return error.TemplateSyntaxError;
        const abs_end = after_start + end_pos;
        const inner = std.mem.trim(u8, result[after_start..abs_end], " ");
        const after_close = abs_end + end_marker.len;

        const resolved = try resolveOne(allocator, inner, ctx, kv);
        defer allocator.free(resolved);

        var new_result = try std.ArrayList(u8).initCapacity(allocator, result.len + resolved.len - (after_close - abs_start));
        try new_result.appendSlice(allocator, result[0..abs_start]);
        try new_result.appendSlice(allocator, resolved);
        try new_result.appendSlice(allocator, result[after_close..]);
        allocator.free(result);
        result = try new_result.toOwnedSlice(allocator);

        search_pos = abs_start + resolved.len;
    }

    return result;
}

fn resolveOne(allocator: std.mem.Allocator, inner: []const u8, ctx: *context.RuntimeContext, kv: kv_backend.KvBackend) ![]const u8 {
    if (!std.mem.startsWith(u8, inner, "ctx.")) {
        return error.TemplateSyntaxError;
    }

    const without_ctx = inner["ctx.".len..];

    const is_global = std.mem.startsWith(u8, without_ctx, "global.");
    const lookup_base = if (is_global) without_ctx["global.".len..] else without_ctx;

    const first_dot = std.mem.indexOfScalar(u8, lookup_base, '.');
    const name = if (first_dot) |pos| lookup_base[0..pos] else lookup_base;
    const json_path = if (first_dot) |pos| lookup_base[pos + 1 ..] else "";

    const raw_value = if (is_global) blk: {
        const val = try kv.get(allocator, name);
        break :blk val orelse return error.GlobalKeyNotFound;
    } else blk: {
        const val = ctx.get(name);
        break :blk val orelse return error.ResourceNotFound;
    };
    defer if (is_global) allocator.free(raw_value);

    if (json_path.len == 0) {
        return allocator.dupe(u8, raw_value);
    }

    return navigateJsonPath(allocator, raw_value, json_path);
}

fn navigateJsonPath(allocator: std.mem.Allocator, raw_value: []const u8, path: []const u8) ![]const u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, raw_value, .{});
    defer parsed.deinit();

    var current = parsed.value;
    var segments = std.mem.splitScalar(u8, path, '.');
    while (segments.next()) |segment| {
        switch (current) {
            .object => |obj| {
                current = obj.get(segment) orelse return error.JsonPathNotFound;
            },
            .array => |arr| {
                const idx = std.fmt.parseInt(usize, segment, 10) catch return error.JsonPathNotNavigable;
                current = arr.items[idx];
            },
            else => return error.JsonPathNotNavigable,
        }
    }

    return switch (current) {
        .string => |s| allocator.dupe(u8, s),
        .integer => |i| std.fmt.allocPrint(allocator, "{d}", .{i}),
        .float => |f| std.fmt.allocPrint(allocator, "{d}", .{f}),
        .bool => |b| allocator.dupe(u8, if (b) "true" else "false"),
        else => return error.JsonPathNonStringLeaf,
    };
}