const std = @import("std");
const c = @import("c.zig").c;

const TrieKey = extern struct {
    parent_node_id: u32,
    mnt_id: u64,
    name: [32]u8,
};

const TrieValue = extern struct {
    next_node_id: u32,
    mnt_id: u64,
    is_terminal: u8,
    padding: [3]u8 = [_]u8{0} ** 3,
};

pub fn addPathToTrie(
    allocator: std.mem.Allocator,
    io: std.Io,
    map_ptr: *c.struct_bpf_map,
    filepath: []const u8,
    global_node_id: *u32,
) !void {
    const mnt_id = try getMntId(allocator, filepath);
    const mount_root_path = try getMountpathByFilepath(allocator, io, mnt_id);
    defer allocator.free(mount_root_path);

    var clean_path = filepath;
    if (!std.mem.eql(u8, mount_root_path, "/")) {
        if (std.mem.startsWith(u8, filepath, mount_root_path)) {
            clean_path = filepath[mount_root_path.len..];
        }
    }

    var tokens = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer tokens.deinit(allocator);

    var it = std.mem.tokenizeScalar(u8, clean_path, '/');
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
            .mnt_id = mnt_id,
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
            .mnt_id = mnt_id,
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

        std.debug.print("[FIM Trie] Added: mnt_id={d} parent={d}, name='{s}' -> next={d}, terminal={d}\n", .{
            mnt_id,
            key.parent_node_id,
            part,
            value.next_node_id,
            value.is_terminal,
        });

        current_parent_id = assigned_next_id;
    }
}

fn getMntId(allocator: std.mem.Allocator, filepath: []const u8) !u64 {
    const path_c = try allocator.dupeSentinel(u8, filepath, 0);
    defer allocator.free(path_c);

    var statx_buf: std.os.linux.Statx = undefined;
    const mask: std.os.linux.STATX = .{ .MNT_ID = true };
    const rc = std.os.linux.statx(std.posix.AT.FDCWD, path_c, 0, mask, &statx_buf);
    const err = std.posix.errno(rc);

    if (err != .SUCCESS) {
        std.debug.print("failed to statx: code {d}\n", .{rc});
        return error.StatxError;
    }

    if (!statx_buf.mask.MNT_ID) {
        std.debug.print("kernel not returned stx_mnt_id\n", .{});
        return error.MntIdNotFound;
    }

    return statx_buf.mnt_id;
}

fn getMountpathByFilepath(allocator: std.mem.Allocator, io: std.Io, target_mnt_id: u64) ![]u8 {
    const file = try std.Io.Dir.openFileAbsolute(io, "/proc/self/mountinfo", .{});
    defer file.close(io);

    const buf = try allocator.alloc(u8, 1024 * 1024);
    defer allocator.free(buf);
    var reader = file.reader(io, buf);

    while (reader.interface.takeDelimiterExclusive('\n')) |line| {
        reader.interface.toss(1);
        var it = std.mem.tokenizeScalar(u8, line, ' ');

        const mnt_id_str = it.next() orelse continue;
        const mnt_id = std.fmt.parseInt(u64, mnt_id_str, 10) catch continue;

        if (mnt_id == target_mnt_id) {
            _ = it.next(); // parent_id
            _ = it.next(); // devid
            _ = it.next(); // root (inside fs)

            const mount_point = it.next() orelse continue;

            return try allocator.dupe(u8, mount_point);
        }
    } else |err| switch (err) {
        error.EndOfStream => return error.MountpointNotFound,
        else => return err,
    }

    return "";
}
