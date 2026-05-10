const std = @import("std");
const cmd = @import("utils/cmd.zig");

const pacman = struct {
    pub fn install(self: pacman, allocator: std.mem.Allocator, io: std.Io, name: []const u8) !std.process.RunResult {
        _ = self;

        const argv = [_][]const u8{ "pacman", "-Sy", name };
        return cmd.run(allocator, io, &argv);
    }
};

const apt = struct {
    pub fn install(self: apt, allocator: std.mem.Allocator, io: std.Io, name: []const u8) !std.process.RunResult {
        _ = self;

        const argv = [_][]const u8{
            "apt-get", "-y",
            "-o",      "Dpkg::Options::=--force-confdef",
            "-o",      "Dpkg::Options::=--force-confold",
            "install", name,
        };
        return cmd.run(allocator, io, &argv);
    }
};

pub const Manager = union(enum) {
    pacman: pacman,
    apt: apt,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Manager {
        const osfamily = "debian";

        if (std.mem.eql(u8, osfamily, "debian")) {
            return .{
                .apt = .apt{},
                .allocator = allocator,
            };
        } else {
            return .{
                .pacman = .pacman{},
                .allocator = allocator,
            };
        }
    }

    pub fn install(self: Manager, io: std.Io, name: []const u8) !std.process.RunResult {
        switch (self) {
            inline else => |case| return try case.install(self.allocator, io, name),
        }
    }
};

test "PackageModule: simple help " {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const pacmanManager = apt{};
    const res = try pacmanManager.install(allocator, io, "bat");
    defer {
        allocator.free(res.stdout);
        allocator.free(res.stderr);
    }
    std.debug.print("Pacman manager stdout: \n{s}\n", .{res.stdout});
    std.debug.print("Pacman manager stderr: \n{s}\n", .{res.stderr});
}
