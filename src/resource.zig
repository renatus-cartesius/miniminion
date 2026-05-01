const std = @import("std");
const dag = @import("dag.zig");

const ResourceErrors = error{ MissingType, NotFoundResource };

pub const File = struct {
    path: []const u8,
    content: []const u8 = "",
    mode: u32 = 0o644,
};

pub const Package = struct {
    name: []const u8,
    version: ?[]const u8 = null,
};

pub const ResourceData = union(enum) {
    file: File,
    package: Package,
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
