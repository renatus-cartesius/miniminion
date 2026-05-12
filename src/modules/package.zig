const std = @import("std");
const cmd = @import("utils/cmd.zig");

pub const PackageError = error{
    FailedGetVersion,
    NotInstalled,
};

const pacman = struct {
    pub fn checkVersion(self: pacman, allocator: std.mem.Allocator, io: std.Io, name: []const u8, version: []const u8) !bool {
        _ = self;
        _ = allocator;
        _ = io;
        _ = name;
        _ = version;

        return false;
    }

    pub fn install(self: pacman, allocator: std.mem.Allocator, io: std.Io, name: []const u8) !void {
        _ = self;

        const argv = [_][]const u8{ "pacman", "-Sy", name };
        const res = try cmd.run(allocator, io, &argv);
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }
    }
};

const apt = struct {
    pub fn checkVersion(self: apt, allocator: std.mem.Allocator, io: std.Io, name: []const u8, version: []const u8) !bool {
        _ = self;

        const argv = [_][]const u8{
            "dpkg-query",
            "-f",
            "${Version}",
            "-W",
            name,
        };
        const res = try cmd.run(allocator, io, &argv);
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }

        // std.debug.print("package {s} version is {s}\n", .{ name, res.stdout });
        // std.debug.print("stderr: {s}\n", .{res.stderr});

        if (res.term == .exited and res.term.exited != 0) {
            return PackageError.FailedGetVersion;
        }

        return std.mem.eql(u8, res.stdout, version);
    }

    pub fn install(self: apt, allocator: std.mem.Allocator, io: std.Io, name: []const u8) !void {
        _ = self;

        const argv = [_][]const u8{
            "apt-get", "-y",
            "-o",      "Dpkg::Options::=--force-confdef",
            "-o",      "Dpkg::Options::=--force-confold",
            "install", name,
        };
        const res = try cmd.run(allocator, io, &argv);
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }
    }
};

// Declarative core of a "package" resource type
pub const Manager = struct {
    inner: Inner,
    allocator: std.mem.Allocator,

    const Inner = union(enum) {
        pacman: pacman,
        apt: apt,
    };

    pub fn init(allocator: std.mem.Allocator) Manager {
        const osfamily = "debian";

        if (std.mem.eql(u8, osfamily, "debian")) {
            return Manager{ .inner = Inner{ .apt = apt{} }, .allocator = allocator };
        } else {
            return Manager{ .inner = Inner{ .pacman = pacman{} }, .allocator = allocator };
        }
    }

    pub fn install(self: Manager, io: std.Io, name: []const u8) !void {
        switch (self.inner) {
            inline else => |case| return try case.install(self.allocator, io, name),
        }
    }

    pub fn checkVersion(self: Manager, io: std.Io, name: []const u8, version: []const u8) !bool {
        switch (self.inner) {
            inline else => |case| return try case.checkVersion(self.allocator, io, name, version),
        }
    }
};

test "PackageModule: simple help " {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const aptManager = apt{};
    const res = try aptManager.install(allocator, io, "bat");
    defer {
        allocator.free(res.stdout);
        allocator.free(res.stderr);
    }
    std.debug.print("Apt manager stdout: \n{s}\n", .{res.stdout});
    std.debug.print("Apt manager stderr: \n{s}\n", .{res.stderr});
}

test "PackageModule[apt]: test checkVersion" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const aptManager = Manager.init(allocator);
    if (try aptManager.checkVersion(io, "neovim", "0.9.5-6ubuntu2")) {
        std.debug.print("package neovim: OK\n", .{});
    }
}
