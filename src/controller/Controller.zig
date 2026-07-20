const std = @import("std");
const manifest = @import("../manifest.zig");
const stack = @import("../stack.zig");
const etcd_mod = @import("../etcd.zig");

const Self = @This();

allocator: std.mem.Allocator,
io: std.Io,
etcd_host: []const u8,
etcd_port: u16,

pub fn create(init: std.process.Init, etcd_host: []const u8, etcd_port: u16) Self {
    return .{ .allocator = init.arena.allocator(), .io = init.io, .etcd_host = etcd_host, .etcd_port = etcd_port };
}

pub fn run(self: *Self, stack_path: []const u8, port: u16) !void {
    const stack_data = try manifest.Manifest.load(self.allocator, self.io, stack_path);
    defer self.allocator.free(stack_data.json_output);

    const base_dir = std.fs.path.dirname(stack_path) orelse ".";
    var stk = try stack.parse(self.allocator, self.io, stack_data.json_output, base_dir);
    defer stk.deinit();

    var ec = etcd_mod.create(self.etcd_host, self.etcd_port, self.io);

    for (stk.dag.nodes.items) |node| {
        const key = try std.fmt.allocPrint(self.allocator, "/miniminion/agents/{s}/status", .{node.value.hostname});
        defer self.allocator.free(key);
        ec.put(self.allocator, key, "pending") catch |err| {
            std.debug.print("controller: etcd put failed for {s}: {}\n", .{ node.value.hostname, err });
        };
    }

    const address = try std.Io.net.IpAddress.parse("0.0.0.0", port);
    var tcp_server = try std.Io.net.IpAddress.listen(&address, self.io, .{ .reuse_address = true, .mode = .stream });
    defer tcp_server.deinit(self.io);

    std.debug.print("controller: listening on {d}, stack {s}\n", .{ port, stack_path });

    while (true) {
        const conn = try tcp_server.accept(self.io);
        defer conn.close(self.io);

        var read_buf: [8192]u8 = undefined;
        var write_buf: [65536]u8 = undefined;
        var reader = conn.reader(self.io, &read_buf);
        var writer = conn.writer(self.io, &write_buf);

        self.handleConnection(&stk, &ec, &reader, &writer) catch |err| {
            std.debug.print("controller: request error: {}\n", .{err});
            _ = writer.interface.writeAll("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n") catch {};
            _ = writer.interface.flush() catch {};
        };
    }
}

fn handleConnection(self: *Self, stk: *stack.Stack, ec: *etcd_mod, reader: *std.Io.net.Stream.Reader, writer: *std.Io.net.Stream.Writer) !void {
    var header_buf: [8192]u8 = undefined;
    var header_len: usize = 0;
    while (header_len < header_buf.len) {
        var iov = [_][]u8{header_buf[header_len..][0..1]};
        const n = reader.interface.readVec(&iov) catch return error.ConnectionClosed;
        if (n == 0) return error.ConnectionClosed;
        header_len += 1;
        if (header_len >= 4 and std.mem.eql(u8, header_buf[header_len - 4 .. header_len], "\r\n\r\n")) break;
    }

    const raw = header_buf[0..header_len];
    const header_end = raw.len - 4;
    const headers = raw[0..header_end];

    const body_content_length = findContentLength(headers) orelse 0;
    const body = try self.allocator.alloc(u8, body_content_length);
    defer self.allocator.free(body);
    var offset: usize = 0;
    while (offset < body_content_length) {
        var iov = [_][]u8{body[offset..]};
        const n = reader.interface.readVec(&iov) catch return error.ConnectionClosed;
        if (n == 0) return error.ConnectionClosed;
        offset += n;
    }

    var lines = std.mem.splitSequence(u8, headers, "\r\n");
    const request_line = lines.next() orelse return error.InvalidHttpRequest;
    var rl_it = std.mem.splitScalar(u8, request_line, ' ');
    const method = rl_it.next() orelse return error.InvalidHttpRequest;
    const target = rl_it.next() orelse return error.InvalidHttpRequest;

    if (std.mem.eql(u8, method, "GET")) {
        try self.handleGet(stk, ec, writer, target, body);
    } else if (std.mem.eql(u8, method, "POST")) {
        try self.handlePost(stk, ec, writer, target, body);
    } else {
        try writeResponse(writer, 405, "Method Not Allowed", "");
    }
}

fn handleGet(self: *Self, stk: *stack.Stack, ec: *etcd_mod, writer: *std.Io.net.Stream.Writer, target: []const u8, body: []const u8) !void {
    _ = body;

    const hostname = parseQueryParam(target, "hostname") orelse {
        try writeResponse(writer, 400, "Bad Request", "{\"error\":\"missing hostname\"}");
        return;
    };

    const node = stk.agentNode(hostname) orelse {
        try writeResponse(writer, 404, "Not Found", "{\"error\":\"unknown hostname\"}");
        return;
    };

    const deps = stk.dependenciesFor(hostname) orelse &.{};
    for (deps) |dep_idx| {
        const dep_hostname = stk.dag.nodes.items[dep_idx].value.hostname;
        const key = try std.fmt.allocPrint(self.allocator, "/miniminion/agents/{s}/status", .{dep_hostname});
        defer self.allocator.free(key);

        const status = ec.get(self.allocator, key) catch null;
        if (status) |s| {
            defer self.allocator.free(s);
            if (!std.mem.eql(u8, s, "success")) {
                const resp = try std.fmt.allocPrint(self.allocator, "{{\"retry_after\":5,\"waiting_for\":\"{s}\"}}", .{dep_hostname});
                defer self.allocator.free(resp);
                try writeResponse(writer, 202, "Accepted", resp);
                return;
            }
        } else {
            try writeResponse(writer, 202, "Accepted", "{\"retry_after\":5}");
            return;
        }
    }

    const key = try std.fmt.allocPrint(self.allocator, "/miniminion/agents/{s}/status", .{hostname});
    defer self.allocator.free(key);
    ec.put(self.allocator, key, "running") catch {};

    try writeResponse(writer, 200, "OK", node.state_content);
}

fn handlePost(self: *Self, stk: *stack.Stack, ec: *etcd_mod, writer: *std.Io.net.Stream.Writer, target: []const u8, body: []const u8) !void {
    _ = stk;

    if (!std.mem.eql(u8, target, "/status")) {
        try writeResponse(writer, 404, "Not Found", "{\"error\":\"not found\"}");
        return;
    }

    const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, body, .{});
    defer parsed.deinit();

    const hostname = parsed.value.object.get("hostname") orelse {
        try writeResponse(writer, 400, "Bad Request", "{\"error\":\"missing hostname\"}");
        return;
    };
    const status = parsed.value.object.get("status") orelse {
        try writeResponse(writer, 400, "Bad Request", "{\"error\":\"missing status\"}");
        return;
    };

    const key = try std.fmt.allocPrint(self.allocator, "/miniminion/agents/{s}/status", .{hostname.string});
    defer self.allocator.free(key);
    ec.put(self.allocator, key, status.string) catch |err| {
        const resp = try std.fmt.allocPrint(self.allocator, "{{\"error\":\"etcd error: {}\"}}", .{err});
        defer self.allocator.free(resp);
        try writeResponse(writer, 500, "Internal Server Error", resp);
        return;
    };

    std.debug.print("controller: agent {s} status -> {s}\n", .{ hostname.string, status.string });
    try writeResponse(writer, 200, "OK", "{\"status\":\"ok\"}");
}

fn parseQueryParam(target: []const u8, name: []const u8) ?[]const u8 {
    const qpos = std.mem.indexOfScalar(u8, target, '?') orelse return null;
    const query = target[qpos + 1 ..];
    var it = std.mem.splitSequence(u8, query, "&");
    while (it.next()) |pair| {
        var pair_it = std.mem.splitScalar(u8, pair, '=');
        const key = pair_it.next() orelse continue;
        const val = pair_it.rest();
        if (std.mem.eql(u8, key, name)) {
            return val;
        }
    }
    return null;
}

fn writeResponse(writer: *std.Io.net.Stream.Writer, status_code: u16, reason: []const u8, body: []const u8) !void {
    var wbuf: [256]u8 = undefined;
    const header = try std.fmt.bufPrint(&wbuf, "HTTP/1.1 {d} {s}\r\nContent-Length: {d}\r\nContent-Type: application/json\r\n\r\n", .{ status_code, reason, body.len });
    try writer.interface.writeAll(header);
    try writer.interface.writeAll(body);
    try writer.interface.flush();
}

fn findContentLength(headers: []const u8) ?u64 {
    var lines = std.mem.splitSequence(u8, headers, "\r\n");
    while (lines.next()) |line| {
        var it = std.mem.splitScalar(u8, line, ':');
        const name = std.mem.trim(u8, it.next() orelse continue, " ");
        if (std.ascii.eqlIgnoreCase(name, "content-length")) {
            const val = std.mem.trim(u8, it.rest(), " ");
            return std.fmt.parseInt(u64, val, 10) catch null;
        }
    }
    return null;
}