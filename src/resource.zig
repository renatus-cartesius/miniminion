const std = @import("std");
const dag = @import("dag.zig");

const File = @import("resources/file.zig");
const Package = @import("resources/package.zig");
const Shell = @import("resources/shell.zig");

pub const ResourceErrors = error{ MissingType, NotFoundResource, IoNotInitialized, AllocatorNotInitialized };

pub const ResourceData = union(enum) {
    file: File,
    package: Package,
    shell: Shell,

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

        // Parse resource based on type
        if (std.mem.eql(u8, type_name, "file")) {
            const path_field = resource_data.object.get("path") orelse continue;
            const content_field = resource_data.object.get("content") orelse continue;
            const mode_field = resource_data.object.get("mode") orelse std.json.Value{ .integer = 0o755 };

            const file_resource = Resource{
                .name = resource_name,
                .data = ResourceData{ .file = File.create(path_field.string, content_field.string, @intCast(mode_field.integer)) },
                .deps = deps,
            };
            try resources.append(allocator, file_resource);
        } else if (std.mem.eql(u8, type_name, "package")) {
            const name_field = resource_data.object.get("name") orelse continue;
            const version_field = resource_data.object.get("version");

            const package_resource = Resource{
                .name = resource_name,
                .data = ResourceData{ .package = Package.create(name_field.string, if (version_field) |v| v.string else null) },
                .deps = deps,
            };
            try resources.append(allocator, package_resource);
        } else if (std.mem.eql(u8, type_name, "shell")) {
            const command_field = resource_data.object.get("command") orelse continue;

            const shell_resource = Resource{
                .name = resource_name,
                .data = ResourceData{ .shell = Shell.create(command_field.string) },
                .deps = deps,
            };
            try resources.append(allocator, shell_resource);
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
        \\  "apt-update": {
        \\    "type": "shell",
        \\    "command": "apt update -y"
        \\  },
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
