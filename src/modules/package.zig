const std = @import("std");
const cmd = @import("utils/cmd.zig");

pub const PackageError = error{
    FailedGetVersion,
    FailedCheckInstalled,
    NotInstalled,
};

const pacman = struct {
    pub fn checkVersion(self: pacman, allocator: std.mem.Allocator, io: std.Io, name: []const u8, version: ?[]const u8) !bool {
        _ = self;
        _ = allocator;
        _ = io;
        _ = name;
        _ = version;

        return false;
    }

    pub fn install(self: pacman, allocator: std.mem.Allocator, io: std.Io, name: []const u8, version: ?[]const u8) !void {
        _ = self;
        _ = version;

        const argv = [_][]const u8{ "pacman", "-Sy", name };
        const res = try cmd.run(allocator, io, &argv);
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }
    }
};

const apt = struct {
    pub fn checkVersion(self: apt, allocator: std.mem.Allocator, io: std.Io, name: []const u8, version: ?[]const u8) !bool {
        _ = self;
        // if version not specified in manifest then we just check if package is installed
        if (version) |v| {
            const argv = [_][]const u8{ "dpkg-query", "-f", "${Version}", "-W", name };
            const install_res = try cmd.run(allocator, io, &argv);
            defer {
                allocator.free(install_res.stdout);
                allocator.free(install_res.stderr);
            }

            // std.debug.print("package {s} version is {s}\n", .{ name, res.stdout });
            // std.debug.print("stderr: {s}\n", .{res.stderr});

            if (install_res.term == .exited and install_res.term.exited != 0) {
                return PackageError.FailedGetVersion;
            }

            return std.mem.eql(u8, install_res.stdout, v);
        } else {
            const argv = [_][]const u8{ "dpkg-query", "-f", "${Status}", "-W", name };
            const check_res = try cmd.run(allocator, io, &argv);
            defer {
                allocator.free(check_res.stdout);
                allocator.free(check_res.stderr);
            }

            if (check_res.term == .exited and check_res.term.exited != 0) {
                if (std.mem.indexOf(u8, check_res.stderr, "no packages found matching") != null) {
                    return false;
                }

                return PackageError.FailedCheckInstalled;
            }

            if (std.mem.eql(u8, check_res.stdout, "install ok installed")) {
                return true;
            }

            return false;
        }
    }

    pub fn install(self: apt, allocator: std.mem.Allocator, io: std.Io, name: []const u8, version: ?[]const u8) !void {
        _ = self;

        var argv = try std.ArrayList([]const u8).initCapacity(allocator, 0);
        defer argv.deinit(allocator);

        try argv.appendSlice(allocator, &[_][]const u8{
            "apt-get", "-y",
            "-o",      "Dpkg::Options::=--force-confdef",
            "-o",      "Dpkg::Options::=--force-confold",
            "install", "--allow-downgrades",
        });

        var full_pkg_name: ?[]const u8 = null;
        defer if (full_pkg_name) |str| allocator.free(str);

        if (version) |v| {
            full_pkg_name = try std.fmt.allocPrint(allocator, "{s}={s}", .{ name, v });
            try argv.append(allocator, full_pkg_name orelse name);
        } else {
            try argv.append(allocator, name);
        }

        const res = try cmd.run(allocator, io, argv.items);
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }

        // std.debug.print("package helper stdout: {s}", .{res.stdout});
        // std.debug.print("package helper stderr: {s}", .{res.stderr});
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
    // installs a package of the specified version or simply installs it without specifying a version(depending on the specific package manager)
    pub fn install(self: Manager, io: std.Io, name: []const u8, version: ?[]const u8) !void {
        switch (self.inner) {
            inline else => |case| return try case.install(self.allocator, io, name, version),
        }
    }

    // checks that the package of the required version is installed of that it is installed at all
    pub fn checkVersion(self: Manager, io: std.Io, name: []const u8, version: ?[]const u8) !bool {
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
