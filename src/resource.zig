const std = @import("std");

const ResourceErrors = error{
    MissingType,
};

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
};

fn parseReources(allocator: std.mem.Allocator, json: []const u8) ![]Resource {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    // defer parsed.deinit();

    var resources = try std.ArrayList(Resource).initCapacity(allocator, 0);
    // defer resources.deinit(allocator);

    var iter = parsed.value.object.iterator();
    while (iter.next()) |entry| {
        const resource_data = entry.value_ptr.*;
        const resource_name = entry.key_ptr.*;

        const type_field = resource_data.object.get("type") orelse return error.MissingType;
        const type_name = type_field.string;

        inline for (std.meta.fields(ResourceData)) |field| {
            if (std.mem.eql(u8, type_name, field.name)) {
                const parsed_field = try std.json.parseFromValue(field.type, allocator, resource_data, .{ .ignore_unknown_fields = true });
                // defer parsed_field.deinit();

                try resources.append(allocator, .{ .name = resource_name, .data = @unionInit(ResourceData, field.name, parsed_field.value) });
                break;
            }
        }
    }

    return resources.toOwnedSlice(allocator);
}

test "State map parsing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const json =
        \\{
        \\  "setup-shell": {
        \\    "type": "file",
        \\    "path": "/home/user/.zshrc",
        \\    "content": "alias z=zig"
        \\  },
        \\  "hosts-config": {
        \\    "type": "file",
        \\    "path": "/etc/hosts",
        \\    "content": "asdf"
        \\  },
        \\  "compiler": {
        \\    "type": "package",
        \\    "name": "zig",
        \\    "version": "0.16"
        \\  }
        \\}
    ;

    const resources = try parseReources(allocator, json);

    for (resources) |r| {
        std.debug.print("\nResource {s}:\n\t", .{@tagName(r.data)});
        switch (r.data) {
            .file => |f| std.debug.print("filepath: {s}, content: {s}\n", .{ f.path, f.content }),
            .package => |p| std.debug.print("name: {s}, version: {s}\n", .{ p.name, p.version orelse "unset" }),
        }
    }
}
