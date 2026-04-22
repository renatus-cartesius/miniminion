const std = @import("std");

pub const File = struct {
    path: []const u8,
    content: []const u8 = "",
    mode: u32 = 0o644,
};

pub const Package = struct {
    name: []const u8,
    version: ?[]const u8 = null,
};

pub const Resource = union(enum) {
    file: File,
    package: Package,
};

pub const State = struct {
    resources: []*Resource,
};
