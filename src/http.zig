const std = @import("std");

pub fn request(allocator: std.mem.Allocator, io: std.Io, host: []const u8, port: u16, method: []const u8, path: []const u8, body: []const u8) ![]u8 {
    const address = try std.Io.net.IpAddress.parse(host, port);
    const stream = try std.Io.net.IpAddress.connect(&address, io, .{ .mode = .stream });
    defer stream.close(io);

    var write_buf: [65536]u8 = undefined;
    var writer = stream.writer(io, &write_buf);

    const req = if (body.len > 0)
        try std.fmt.allocPrint(allocator, "{s} {s} HTTP/1.1\r\nHost: {s}:{d}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}", .{ method, path, host, port, body.len, body })
    else
        try std.fmt.allocPrint(allocator, "{s} {s} HTTP/1.1\r\nHost: {s}:{d}\r\n\r\n", .{ method, path, host, port });
    defer allocator.free(req);

    try writer.interface.writeAll(req);
    try writer.interface.flush();

    var read_buf: [65536]u8 = undefined;
    var reader = stream.reader(io, &read_buf);

    var header: [8192]u8 = undefined;
    var header_len: usize = 0;
    while (header_len < header.len) {
        const slice = header[header_len..][0..1];
        var iov = [_][]u8{slice};
        const n = reader.interface.readVec(&iov) catch return error.ConnectionClosed;
        if (n == 0) return error.ConnectionClosed;
        header_len += 1;
        if (header_len >= 4 and std.mem.eql(u8, header[header_len - 4 .. header_len], "\r\n\r\n")) break;
    }

    const headers = header[0 .. header_len - 4];
    const status_line = headers[0..std.mem.indexOfScalar(u8, headers, '\r').?];
    var it = std.mem.splitSequence(u8, status_line, " ");
    _ = it.next();
    const status_code = try std.fmt.parseInt(u16, it.next() orelse return error.InvalidHttpResponse, 10);

    const body_len = findContentLength(headers) orelse 0;
    var body_result = try allocator.alloc(u8, body_len);
    errdefer allocator.free(body_result);

    var offset: usize = 0;
    while (offset < body_len) {
        const chunk = body_result[offset..];
        var iov = [_][]u8{chunk};
        const n = reader.interface.readVec(&iov) catch return error.ConnectionClosed;
        if (n == 0) return error.ConnectionClosed;
        offset += n;
    }

    if (status_code >= 200 and status_code < 300) {
        return body_result;
    }

    return error.HttpRequestFailed;
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