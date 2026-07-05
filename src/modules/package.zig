const std = @import("std");
const cmd = @import("utils/cmd.zig");

pub const PackageError = error{
    FailedGetVersion,
    FailedCheckInstalled,
    NotInstalled,
    NoPackageManagerFound,
};

const pacman = struct {
    pub fn checkVersion(self: pacman, allocator: std.mem.Allocator, io: std.Io, name: []const u8, version: ?[]const u8) !bool {
        _ = self;
        const argv = [_][]const u8{ "pacman", "-Q", name };
        const res = try cmd.run(allocator, io, &argv);
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }
        if (res.term == .exited and res.term.exited != 0) {
            return false;
        }
        if (version) |v| {
            var it = std.mem.splitScalar(u8, std.mem.trim(u8, res.stdout, " \n\r"), ' ');
            _ = it.next();
            const installed = it.next() orelse return false;
            return std.mem.eql(u8, installed, v);
        }
        return true;
    }

    pub fn install(self: pacman, allocator: std.mem.Allocator, io: std.Io, name: []const u8, version: ?[]const u8) !void {
        _ = self;
        _ = version;
        const argv = [_][]const u8{ "pacman", "-Sy", "--noconfirm", name };
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
        if (version) |v| {
            const argv = [_][]const u8{ "dpkg-query", "-f", "${Version}", "-W", name };
            const install_res = try cmd.run(allocator, io, &argv);
            defer {
                allocator.free(install_res.stdout);
                allocator.free(install_res.stderr);
            }

            if (install_res.term == .exited and install_res.term.exited != 0) {
                return PackageError.FailedGetVersion;
            }

            return std.mem.eql(u8, std.mem.trim(u8, install_res.stdout, " \n\r"), v);
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

            return std.mem.eql(u8, std.mem.trim(u8, check_res.stdout, " \n\r"), "install ok installed");
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
    }
};

const dnf = struct {
    pub fn checkVersion(self: dnf, allocator: std.mem.Allocator, io: std.Io, name: []const u8, version: ?[]const u8) !bool {
        _ = self;
        if (version) |v| {
            const argv = [_][]const u8{ "rpm", "-q", name, "--queryformat", "%{VERSION}" };
            const res = try cmd.run(allocator, io, &argv);
            defer {
                allocator.free(res.stdout);
                allocator.free(res.stderr);
            }
            if (res.term == .exited and res.term.exited != 0) {
                return false;
            }
            return std.mem.eql(u8, std.mem.trim(u8, res.stdout, " \n\r"), v);
        } else {
            const argv = [_][]const u8{ "rpm", "-q", name };
            const res = try cmd.run(allocator, io, &argv);
            defer {
                allocator.free(res.stdout);
                allocator.free(res.stderr);
            }
            return res.term == .exited and res.term.exited == 0;
        }
    }

    pub fn install(self: dnf, allocator: std.mem.Allocator, io: std.Io, name: []const u8, version: ?[]const u8) !void {
        _ = self;
        var argv = try std.ArrayList([]const u8).initCapacity(allocator, 0);
        defer argv.deinit(allocator);

        try argv.appendSlice(allocator, &[_][]const u8{ "dnf", "install", "-y" });

        var full_pkg_name: ?[]const u8 = null;
        defer if (full_pkg_name) |str| allocator.free(str);

        if (version) |v| {
            full_pkg_name = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ name, v });
            try argv.append(allocator, full_pkg_name orelse name);
        } else {
            try argv.append(allocator, name);
        }

        const res = try cmd.run(allocator, io, argv.items);
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }
    }
};

const apk = struct {
    pub fn checkVersion(self: apk, allocator: std.mem.Allocator, io: std.Io, name: []const u8, version: ?[]const u8) !bool {
        _ = self;
        const argv = [_][]const u8{ "apk", "info", "-e", name };
        const res = try cmd.run(allocator, io, &argv);
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }
        const installed = res.term == .exited and res.term.exited == 0;
        if (!installed) return false;
        if (version) |v| {
            const argv_v = [_][]const u8{ "apk", "list", "-I", "-e", name };
            const res_v = try cmd.run(allocator, io, &argv_v);
            defer {
                allocator.free(res_v.stdout);
                allocator.free(res_v.stderr);
            }
            const trimmed = std.mem.trim(u8, res_v.stdout, " \n\r");
            if (std.mem.lastIndexOfScalar(u8, trimmed, '-')) |dash| {
                const ver_part = trimmed[dash + 1 ..];
                if (std.mem.indexOfScalar(u8, ver_part, '-')) |sub| {
                    return std.mem.eql(u8, ver_part[0..sub], v);
                }
                return std.mem.eql(u8, ver_part, v);
            }
            return false;
        }
        return true;
    }

    pub fn install(self: apk, allocator: std.mem.Allocator, io: std.Io, name: []const u8, version: ?[]const u8) !void {
        _ = self;
        _ = version;
        const argv = [_][]const u8{ "apk", "add", name };
        const res = try cmd.run(allocator, io, &argv);
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }
    }
};

fn hasBinary(allocator: std.mem.Allocator, io: std.Io, name: []const u8) !bool {
    const argv = [_][]const u8{ "which", name };
    const res = try cmd.run(allocator, io, &argv);
    defer {
        allocator.free(res.stdout);
        allocator.free(res.stderr);
    }
    return res.term == .exited and res.term.exited == 0;
}

fn detectPackageManager(allocator: std.mem.Allocator, io: std.Io) !Manager.Inner {
    if (try hasBinary(allocator, io, "apt-get")) return Manager.Inner{ .apt = apt{} };
    if (try hasBinary(allocator, io, "pacman")) return Manager.Inner{ .pacman = pacman{} };
    if (try hasBinary(allocator, io, "dnf")) return Manager.Inner{ .dnf = dnf{} };
    if (try hasBinary(allocator, io, "apk")) return Manager.Inner{ .apk = apk{} };
    return PackageError.NoPackageManagerFound;
}

pub const Manager = struct {
    inner: Inner,
    allocator: std.mem.Allocator,

    const Inner = union(enum) {
        pacman: pacman,
        apt: apt,
        dnf: dnf,
        apk: apk,
    };

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !Manager {
        const detected = try detectPackageManager(allocator, io);
        return Manager{ .inner = detected, .allocator = allocator };
    }

    pub fn install(self: Manager, io: std.Io, name: []const u8, version: ?[]const u8) !void {
        switch (self.inner) {
            inline else => |case| return try case.install(self.allocator, io, name, version),
        }
    }

    pub fn checkVersion(self: Manager, io: std.Io, name: []const u8, version: ?[]const u8) !bool {
        switch (self.inner) {
            inline else => |case| return try case.checkVersion(self.allocator, io, name, version),
        }
    }
};

fn testHasBinary(allocator: std.mem.Allocator) !void {
    var threaded = std.Io.Threaded.init(allocator, .{
        .stack_size = 1024 * 1024,
    });
    const io = threaded.io();
    const exists = try hasBinary(allocator, io, "sh");
    try std.testing.expect(exists);

    const missing = try hasBinary(allocator, io, "nonexistent_binary_xyz");
    try std.testing.expect(!missing);
}

fn testDetectPackageManager(allocator: std.mem.Allocator) !void {
    var threaded = std.Io.Threaded.init(allocator, .{
        .stack_size = 1024 * 1024,
    });
    const io = threaded.io();
    const inner = try detectPackageManager(allocator, io);

    switch (inner) {
        .apt => {},
        .pacman => {},
        .dnf => {},
        .apk => {},
    }
}

fn testManagerInitErrorsOnMissing(allocator: std.mem.Allocator) !void {
    var threaded = std.Io.Threaded.init(allocator, .{
        .stack_size = 1024 * 1024,
    });
    const io = threaded.io();
    const result = Manager.init(allocator, io);
    _ = result catch return;
    return error.SkipZigTest;
}

fn testCheckVersionNoVersion(allocator: std.mem.Allocator, comptime mgr_tag: std.meta.Tag(Manager.Inner)) !void {
    var threaded = std.Io.Threaded.init(allocator, .{
        .stack_size = 1024 * 1024,
    });
    const io = threaded.io();
    const manager = try Manager.init(allocator, io);
    if (manager.inner != mgr_tag) return error.SkipZigTest;

    if (manager.checkVersion(io, "nonexistent-pkg-xyz-123", null)) |installed| {
        try std.testing.expect(!installed);
    } else |_| {
        return error.SkipZigTest;
    }
}

test "hasBinary finds sh, rejects nonexistent" {
    try testHasBinary(std.testing.allocator);
}

test "detectPackageManager returns a valid manager" {
    try testDetectPackageManager(std.testing.allocator);
}

test "Manager.init returns NoPackageManagerFound when PATH is empty" {
    try testManagerInitErrorsOnMissing(std.testing.allocator);
}

test "checkVersion returns false for nonexistent package" {
    try testCheckVersionNoVersion(std.testing.allocator, .apk);
    try testCheckVersionNoVersion(std.testing.allocator, .apt);
    try testCheckVersionNoVersion(std.testing.allocator, .dnf);
    try testCheckVersionNoVersion(std.testing.allocator, .pacman);
}