const std = @import("std");
const c = @import("c.zig").c;

const TrieKey = extern struct {
    parent_node_id: u32,
    name: [32]u8,
};

const TrieValue = extern struct {
    next_node_id: u32,
    is_terminal: u8,
    padding: [3]u8 = [_]u8{0} ** 3,
};

pub fn addPathToTrie(
    allocator: std.mem.Allocator,
    map_ptr: *c.struct_bpf_map,
    full_path: []const u8,
    global_node_id: *u32,
) !void {
    var tokens = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer tokens.deinit(allocator);

    var it = std.mem.tokenizeScalar(u8, full_path, '/');
    while (it.next()) |token| {
        try tokens.append(allocator, token);
    }

    if (tokens.items.len == 0) return;

    std.mem.reverse([]const u8, tokens.items);

    var current_parent_id: u32 = 0;

    for (tokens.items, 0..) |part, idx| {
        if (part.len >= 32) return error.PathComponentTooLong;

        var key = TrieKey{
            .parent_node_id = current_parent_id,
            .name = [_]u8{0} ** 32,
        };
        @memcpy(key.name[0..part.len], part);

        var is_terminal: u8 = 0;
        var assigned_next_id: u32 = 0;

        if (idx == tokens.items.len - 1) {
            is_terminal = 1;
            assigned_next_id = 0;
        } else {
            assigned_next_id = global_node_id.*;
            global_node_id.* += 1;
        }

        const value = TrieValue{
            .next_node_id = assigned_next_id,
            .is_terminal = is_terminal,
        };

        const ret = c.bpf_map__update_elem(
            map_ptr,
            &key,
            @sizeOf(TrieKey),
            &value,
            @sizeOf(TrieValue),
            0,
        );

        if (ret != 0) {
            std.debug.print("Failed to update BPF map for token: {s}, err: {d}\n", .{ part, ret });
            return error.BpfMapUpdateFailed;
        }

        std.debug.print("[Zig Trie] Added: parent={d}, name='{s}' -> next={d}, terminal={d}\n", .{
            key.parent_node_id,
            part,
            value.next_node_id,
            value.is_terminal,
        });

        current_parent_id = assigned_next_id;
    }
}
