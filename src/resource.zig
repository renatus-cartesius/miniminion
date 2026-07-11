const std = @import("std");
const dag = @import("dag.zig");

const File = @import("resources/file.zig");
const Shell = @import("resources/shell.zig");
const AptPkg = @import("resources/apt_pkg.zig");
const DnfPkg = @import("resources/dnf_pkg.zig");
const PacmanPkg = @import("resources/pacman_pkg.zig");
const ApkPkg = @import("resources/apk_pkg.zig");
const Service = @import("resources/service.zig");
const AptRepo = @import("resources/apt_repo.zig");
const Sysctl = @import("resources/sysctl.zig");
const KernelModule = @import("resources/kernel_module.zig");
const AptUpdate = @import("resources/apt_update.zig");
const DnfUpdate = @import("resources/dnf_update.zig");
const PacmanUpdate = @import("resources/pacman_update.zig");
const ApkUpdate = @import("resources/apk_update.zig");

pub const ResourceErrors = error{ MissingType, NotFoundResource, UnknownResourceType, IoNotInitialized, AllocatorNotInitialized, MissingField };

pub const ResourceData = union(enum) {
    file: File,
    shell: Shell,
    apt_pkg: AptPkg,
    dnf_pkg: DnfPkg,
    pacman_pkg: PacmanPkg,
    apk_pkg: ApkPkg,
    service: Service,
    apt_repo: AptRepo,
    sysctl: Sysctl,
    kernel_module: KernelModule,
    apt_update: AptUpdate,
    dnf_update: DnfUpdate,
    pacman_update: PacmanUpdate,
    apk_update: ApkUpdate,

    pub fn typeName(self: ResourceData) []const u8 {
        return @tagName(self);
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

fn parseResource(allocator: std.mem.Allocator, resource_name: []const u8, resource_data: std.json.Value, deps: []const []const u8) !Resource {
    const type_field = resource_data.object.get("type") orelse return error.MissingType;
    const type_name = type_field.string;

    const type_registry = comptime blk: {
        const info = @typeInfo(ResourceData);
        const union_info = info.@"union";
        var result: [union_info.fields.len]struct { name: []const u8, Type: type } = undefined;
        for (&result, union_info.fields) |*r, field| {
            r.* = .{ .name = field.name, .Type = field.type };
        }
        break :blk result;
    };

    inline for (type_registry) |entry| {
        if (std.mem.eql(u8, type_name, entry.name)) {
            return Resource{
                .name = resource_name,
                .data = @unionInit(ResourceData, entry.name, try entry.Type.parseJson(allocator, resource_data)),
                .deps = deps,
            };
        }
    }
    return error.UnknownResourceType;
}

pub fn parseReources(arena: *std.heap.ArenaAllocator, json: []const u8) ![]Resource {
    const allocator = arena.allocator();

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    var resources = try std.ArrayList(Resource).initCapacity(allocator, 0);
    defer resources.deinit(allocator);

    var iter = parsed.value.object.iterator();
    while (iter.next()) |entry| {
        const resource_name = entry.key_ptr.*;
        const resource_data = entry.value_ptr.*;

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

        try resources.append(allocator, try parseResource(allocator, resource_name, resource_data, deps));
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
        \\    "type": "apt_pkg",
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