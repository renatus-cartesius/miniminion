const std = @import("std");
const dag = @import("dag.zig");
const package = @import("modules/package.zig");
const cmd = @import("modules/utils/cmd.zig");

pub const ResourceErrors = error{ MissingType, NotFoundResource, IoNotInitialized, AllocatorNotInitialized };

pub const File = struct {
    path: []const u8,
    content: []const u8 = "",
    mode: u32 = 0o655,
    io: ?std.Io = null,
    allocator: ?std.mem.Allocator = null,

    pub fn init(self: *File, io: std.Io, allocator: std.mem.Allocator) !void {
        self.io = io;
        self.allocator = allocator;
    }

    pub fn help(self: File) void {
        _ = self;
        std.debug.print("file help: resource for managing files\n", .{});
    }

    pub fn apply(self: *File) !bool {
        // Try to open existing file, create if it doesn't exist
        const io = self.io orelse return error.IoNotInitialized;
        const allocator = self.allocator orelse return error.AllocatorNotInitialized;
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
    mgr: ?package.Manager = null,
    io: ?std.Io = null,
    allocator: ?std.mem.Allocator = null,

    pub fn init(self: *Package, io: std.Io, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        self.io = io;
        self.mgr = package.Manager.init(allocator);
    }

    pub fn apply(self: *Package) !bool {
        if (self.version == null) {
            std.debug.print("package {s}: version undefined\n", .{self.name});
            return false;
        }

        // check if package already present with correct version
        if (self.mgr.?.checkVersion(self.io.?, self.name, self.version.?)) |correct| {
            if (correct) {
                // package in correct version
                std.debug.print("package {s}={s} : OK\n", .{ self.name, self.version.? });
                return false;
            } else {
                // reinstalling package with correct version
                try self.mgr.?.install(self.io.?, self.name);
                std.debug.print("package {s}: CHANGED reinstalled\n", .{self.name});
                return true;
            }
        } else |err| {
            if (err == package.PackageError.NotInstalled) {
                // installing the package
                try self.mgr.?.install(self.io.?, self.name);
                std.debug.print("package {s}={s} : CHANGED installed\n", .{ self.name, self.version.? });
                return true;
            } else {
                // something undefined happen
                return err;
            }
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

    pub fn apply(self: *ResourceData) !bool {
        switch (self.*) {
            inline else => |*case| return try case.apply(),
        }
    }

    pub fn init(self: *ResourceData, io: std.Io, allocator: std.mem.Allocator) !void {
        switch (self.*) {
            inline else => |*case| return try case.init(io, allocator),
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

    // Use std.json with more careful error handling
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    var resources = try std.ArrayList(Resource).initCapacity(allocator, 0);
    defer resources.deinit(allocator);

    var iter = parsed.value.object.iterator();
    while (iter.next()) |entry| {
        const resource_name = entry.key_ptr.*;
        const resource_data = entry.value_ptr.*;

        // Simple parsing without complex comptime operations
        const type_field = resource_data.object.get("type") orelse return error.MissingType;
        const type_name = type_field.string;

        // Parse deps
        var deps_array = try std.ArrayList([]const u8).initCapacity(allocator, 0);
        defer deps_array.deinit(allocator);

        if (resource_data.object.get("deps")) |deps_value| {
            if (deps_value == .array) {
                for (deps_value.array.items) |dep| {
                    if (dep == .string) {
                        try deps_array.append(allocator, dep.string);
                    }
                }
            }
        }
        const deps = try deps_array.toOwnedSlice(allocator);

        // Parse file or package based on type
        if (std.mem.eql(u8, type_name, "file")) {
            const path_field = resource_data.object.get("path") orelse continue;
            const content_field = resource_data.object.get("content") orelse continue;
            const mode_field = resource_data.object.get("mode") orelse std.json.Value{ .integer = 0o755 };

            const file_resource = Resource{
                .name = resource_name,
                .data = ResourceData{ .file = File{
                    .path = path_field.string,
                    .content = content_field.string,
                    .mode = @intCast(mode_field.integer),
                } },
                .deps = deps,
            };
            try resources.append(allocator, file_resource);
        } else if (std.mem.eql(u8, type_name, "package")) {
            const name_field = resource_data.object.get("name") orelse continue;
            const version_field = resource_data.object.get("version");

            const package_resource = Resource{
                .name = resource_name,
                .data = ResourceData{ .package = Package{
                    .name = name_field.string,
                    .version = if (version_field) |v| v.string else null,
                    .mgr = package.Manager.init(allocator),
                } },
                .deps = deps,
            };
            try resources.append(allocator, package_resource);
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
