const std = @import("std");
const state_manager = @import("../state_manager.zig");
const http = @import("../http.zig");

const Self = @This();

process_init: std.process.Init,
controller_url: []const u8,

pub fn create(init: std.process.Init, controller_url: []const u8) Self {
    return .{ .process_init = init, .controller_url = controller_url };
}

pub fn run(self: *Self, manifest_path: []const u8) !void {
    var sm = state_manager{};
    try sm.run(self.process_init, manifest_path);
}

pub fn runFromController(self: *Self, host: []const u8, port: u16) !void {
    const io = self.process_init.io;
    const allocator = self.process_init.arena.allocator();

    const hostname = getHostname(allocator) catch "unknown";
    defer allocator.free(hostname);

    std.debug.print("agent: connecting to controller {s}:{d} as {s}\n", .{ host, port, hostname });

    const max_retries: usize = 100;
    var retry: usize = 0;
    while (retry < max_retries) : (retry += 1) {
        const path = try std.fmt.allocPrint(allocator, "/manifest?hostname={s}", .{hostname});
        defer allocator.free(path);

        const resp = http.request(allocator, io, host, port, "GET", path, "") catch |err| {
            std.debug.print("agent: fetch failed (attempt {d}/{d}): {}\n", .{ retry + 1, max_retries, err });
            sleepSec(5);
            continue;
        };
        defer allocator.free(resp);

        if (resp.len > 0 and resp[0] == '{' and std.mem.indexOf(u8, resp, "retry_after") != null) {
            const parsed = std.json.parseFromSlice(std.json.Value, allocator, resp, .{}) catch {
                sleepSec(5);
                continue;
            };
            defer parsed.deinit();
            const retry_after = if (parsed.value.object.get("retry_after")) |ra| @as(u64, switch (ra) {
                .integer => |i| @intCast(i),
                .float => |f| @intFromFloat(f),
                else => 5,
            }) else 5;
            const waiting_for = if (parsed.value.object.get("waiting_for")) |wf| wf.string else "unknown";
            std.debug.print("agent: waiting for {s} (retry in {d}s)\n", .{ waiting_for, retry_after });
            sleepSec(retry_after);
            continue;
        }

        const tmp_path = "/tmp/minim_manifest.jsonnet";
        const options: std.Io.Dir.CreateFileOptions = .{ .read = true, .truncate = true };
        var tmp_file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), io, tmp_path, options);
        defer tmp_file.close(io);
        const tmp_buf = try allocator.alloc(u8, 65536);
        defer allocator.free(tmp_buf);
        var tmp_writer = tmp_file.writer(io, tmp_buf);
        try tmp_writer.interface.writeAll(resp);
        try tmp_writer.interface.flush();

        std.debug.print("agent: running state manifest\n", .{});
        var sm = state_manager{};
        sm.run(self.process_init, tmp_path) catch |err| {
            std.debug.print("agent: state failed: {}\n", .{err});
            const status_body = try std.fmt.allocPrint(allocator, "{{\"hostname\":\"{s}\",\"status\":\"failed\"}}", .{hostname});
            defer allocator.free(status_body);
            _ = http.request(allocator, io, host, port, "POST", "/status", status_body) catch {};
            return;
        };

        const status_body = try std.fmt.allocPrint(allocator, "{{\"hostname\":\"{s}\",\"status\":\"success\"}}", .{hostname});
        defer allocator.free(status_body);
        _ = http.request(allocator, io, host, port, "POST", "/status", status_body) catch |err| {
            std.debug.print("agent: failed to report status: {}\n", .{err});
        };
        std.debug.print("agent: completed successfully\n", .{});
        return;
    }

    std.debug.print("agent: max retries exceeded\n", .{});
}

fn getHostname(allocator: std.mem.Allocator) ![]u8 {
    var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const name = try std.posix.gethostname(&buf);
    return allocator.dupe(u8, name);
}

fn sleepSec(secs: u64) void {
    var ts = std.os.linux.timespec{ .sec = @as(i64, @intCast(secs)), .nsec = 0 };
    _ = std.os.linux.nanosleep(&ts, null);
}