const std = @import("std");
const dag = @import("dag.zig");

pub const ResourceErrors = error{ MissingType, NotFoundResource };

pub const File = struct {
    path: []const u8,
    content: []const u8 = "",
    mode: u32 = 0o655,

    pub fn help(self: File) void {
        _ = self;
        std.debug.print("file help: resource for managing files\n", .{});
    }

    pub fn apply(self: File, io: std.Io, allocator: std.mem.Allocator) !bool {
        // Try to open existing file, create if it doesn't exist
        const open_result = std.Io.Dir.openFile(.cwd(), io, self.path, .{ .mode = .read_write });
        if (open_result) |file| {
            // File exists, check content and permissions
            const buf = try allocator.alloc(u8, 1024 * 1024);
            defer allocator.free(buf);
            var reader = file.reader(io, buf);
            const content = try reader.interface.readAlloc(allocator, try file.length(io));

            // Check and set file mode/permissions if needed
            const file_stat = try std.Io.Dir.statFile(.cwd(), io, self.path, .{});
            const expected_perms = std.Io.File.Permissions.fromMode(self.mode);
            var permissions_updated = false;

            // Compare only the permission bits, not the full enum values
            // The stat result includes file type bits (e.g., 0o100000 for regular files)
            // while fromMode only creates permission bits
            const current_mode_bits = @intFromEnum(file_stat.permissions) & 0o777;
            const expected_mode_bits = @intFromEnum(expected_perms) & 0o777;

            if (current_mode_bits != expected_mode_bits) {
                try std.Io.Dir.setFilePermissions(.cwd(), io, self.path, expected_perms, .{});
                permissions_updated = true;
            }

            if (std.mem.eql(u8, content, self.content)) {
                file.close(io);
                if (permissions_updated) {
                    std.debug.print("file {s} permissions updated\n", .{self.path});
                } else {
                    std.debug.print("file {s} OK\n", .{self.path});
                }
                return permissions_updated;
            }

            // Content differs, update file by closing and reopening with truncate
            file.close(io);

            const options: std.Io.Dir.CreateFileOptions = .{ .read = true, .truncate = true, .permissions = std.Io.File.Permissions.fromMode(self.mode) };
            var new_file = try std.Io.Dir.createFile(.cwd(), io, self.path, options);

            var writer = new_file.writer(io, buf);
            const wrote = try writer.interface.write(self.content);
            _ = try writer.flush();

            new_file.close(io);

            std.debug.print("file {s} CHANGED, wrote {d} bytes\n", .{ self.path, wrote });
            return true;
        } else |err| {
            if (err == error.FileNotFound) {
                // File doesn't exist, create it with specified mode
                const perms = std.Io.File.Permissions.fromMode(self.mode);
                const options: std.Io.Dir.CreateFileOptions = .{ .read = true, .truncate = true, .permissions = perms };
                var new_file = try std.Io.Dir.createFile(.cwd(), io, self.path, options);

                // Write content to new file
                const buf = try allocator.alloc(u8, 1024 * 1024);
                defer allocator.free(buf);
                var writer = new_file.writer(io, buf);
                const wrote = try writer.interface.write(self.content);
                _ = try writer.flush();

                new_file.close(io);

                std.debug.print("file {s} CREATED, wrote {d} bytes\n", .{ self.path, wrote });
                return true;
            } else {
                return err;
            }
        }
    }
};

pub const Package = struct {
    name: []const u8,
    version: ?[]const u8 = null,

    pub fn help(self: Package) void {
        _ = self;
        std.debug.print("package help: resource for managing packages\n", .{});
    }

    pub fn apply(self: Package, io: std.Io, allocator: std.mem.Allocator) !bool {
        std.debug.print("package {s}", .{self.name});
        if (self.version) |v| {
            std.debug.print("@{s}", .{v});
        }
        std.debug.print(": ", .{});

        // Check if package is already installed using direct command execution
        const query_argv = [_][]const u8{ "dpkg-query", "-W", "-f=${Status}", self.name };

        const query_result = std.process.run(allocator, io, .{
            .argv = &query_argv,
            .stderr_limit = .unlimited,
            .stdout_limit = .unlimited,
        }) catch {
            // If dpkg-query fails, it might mean the package is not installed or dpkg-query is not available
            std.debug.print("checking system... ", .{});

            // Check if we're on a Debian/Ubuntu system
            const which_result = std.process.run(allocator, io, .{
                .argv = &[_][]const u8{ "which", "dpkg-query" },
                .stderr_limit = .unlimited,
                .stdout_limit = .unlimited,
            }) catch {
                std.debug.print("SKIP (no package manager)\n", .{});
                return false;
            };
            defer {
                allocator.free(which_result.stderr);
                allocator.free(which_result.stdout);
            }

            if (which_result.term != .exited or which_result.term.exited != 0) {
                std.debug.print("SKIP (no package manager)\n", .{});
                return false;
            }

            std.debug.print("INSTALL (package manager available)\n", .{});
            // In a real implementation, we would install the package here
            // For now, we'll just indicate that installation would happen
            return true;
        };
        defer {
            allocator.free(query_result.stderr);
            allocator.free(query_result.stdout);
        }

        // Check if package is installed
        if (query_result.term == .exited and query_result.term.exited == 0) {
            // Check the output to see if package is installed
            if (std.mem.indexOf(u8, query_result.stdout, "install ok installed") != null) {
                std.debug.print("OK (already installed)\n", .{});
                return false; // No changes needed
            } else {
                std.debug.print("INSTALL (not installed)\n", .{});
                // In a real implementation, we would install the package here
                return true; // Would make changes
            }
        } else {
            std.debug.print("INSTALL (not found)\n", .{});
            // Package not found, would install it
            // In a real implementation, we would install the package here
            return true; // Would make changes
        }
    }
};

pub const ResourceData = union(enum) {
    file: File,
    package: Package,

    pub fn help(self: ResourceData) void {
        switch (self) {
            inline else => |case| case.help(),
        }
    }

    pub fn apply(self: ResourceData, io: std.Io, allocator: std.mem.Allocator) !bool {
        switch (self) {
            inline else => |case| return try case.apply(io, allocator),
        }
    }
};

pub const Resource = struct {
    name: []const u8,
    data: ResourceData,
    deps: []const []const u8 = &.{},
};

pub const State = struct {
    rdag: dag.DAG(Resource),
    rmap: std.StringHashMap(usize),
};

pub fn parseReources(arena: *std.heap.ArenaAllocator, json: []const u8) ![]Resource {
    const allocator = arena.allocator();
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});

    var resources = try std.ArrayList(Resource).initCapacity(allocator, 0);

    var iter = parsed.value.object.iterator();
    while (iter.next()) |entry| {
        const resource_data = entry.value_ptr.*;
        const resource_name = entry.key_ptr.*;

        const type_field = resource_data.object.get("type") orelse return error.MissingType;
        const type_name = type_field.string;

        const deps_value = resource_data.object.get("deps");
        const deps = if (deps_value) |dv|
            (try std.json.parseFromValue([]const []const u8, allocator, dv, .{})).value
        else
            @as([]const []const u8, &.{});

        inline for (std.meta.fields(ResourceData)) |field| {
            if (std.mem.eql(u8, type_name, field.name)) {
                const parsed_field = try std.json.parseFromValue(field.type, allocator, resource_data, .{ .ignore_unknown_fields = true });

                try resources.append(allocator, .{ .name = resource_name, .data = @unionInit(ResourceData, field.name, parsed_field.value), .deps = deps });
                break;
            }
        }
    }

    return resources.toOwnedSlice(allocator);
}

test "Resource: simple state execution" {
    const print = std.debug.print;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const json =
        \\{
        \\  "setup-shell": {
        \\    "type": "file",
        \\    "path": "/home/user/.zshrc",
        \\    "content": "alias z=zig",
        \\    "deps": ["hosts-config", "compiler"]
        \\  },
        \\  "hosts-config": {
        \\    "type": "file",
        \\    "path": "/etc/hosts",
        \\    "content": "asdfsdf",
        \\    "deps": ["compiler"]
        \\  },
        \\  "compiler": {
        \\    "type": "package",
        \\    "name": "zig",
        \\    "version": "0.16"
        \\  }
        \\}
    ;

    const resources = try parseReources(&arena, json);
    var rdag = try dag.DAG(Resource).init(allocator);
    defer rdag.deinit();
    var rmap = std.StringHashMap(usize).init(allocator);
    defer rmap.deinit();

    print("Parsed state:\n", .{});

    for (resources) |r| {
        try rmap.put(r.name, try rdag.addNode(r));

        print("Resource {s}:\n", .{r.name});
        switch (r.data) {
            .file => |f| print("\tfilepath: {s}, content: {s}\n", .{ f.path, f.content }),
            .package => |p| print("\tname: {s}, version: {s}\n", .{ p.name, p.version orelse "unset" }),
        }

        for (r.deps) |d| {
            print("\t\tDependency: {s}\n", .{d});
        }
    }

    for (resources) |r| {
        for (r.deps) |d| {
            try rdag.addEdge(rmap.get(r.name) orelse return ResourceErrors.NotFoundResource, rmap.get(d) orelse return ResourceErrors.NotFoundResource);
        }
    }

    const order = try rdag.topologicalSort(allocator);
    defer allocator.free(order);

    print("\nState execution order: ", .{});
    for (order) |i| {
        std.debug.print("{s} -> ", .{rdag.nodes.items[i].value.name});
    }
    std.debug.print("End.\n", .{});
}
