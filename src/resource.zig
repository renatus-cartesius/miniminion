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

pub const Resource = union(enum) {
    file: File,
    package: Package,
};

pub const State = struct {
    resources: std.ArrayList(Resource),
    allocator: std.mem.Allocator,
    json_data: ?std.json.Parsed(std.json.Value) = null,

    pub fn init(allocator: std.mem.Allocator) State {
        return .{
            .allocator = allocator,
            .resources = std.ArrayList(Resource).initCapacity(allocator, 0),
        };
    }

    pub fn deinit(self: *State) void {
        if (self.json_data) |p| p.deinit();
        self.resources.deinit(self.allocator);
    }

    pub fn load(self: *State, json: []const u8) !void {
        if (self.json_data) |p| p.deinit();
        self.resources.clearRetainingCapacity();

        self.json_data = try std.json.parseFromSlice(std.json.Value, self.allocator, json, .{});

        var iter = self.json_data.?.value.object.iterator();
        while (iter.next()) |entry| {
            const resource_name = entry.key_ptr.*;
            const resource_value = entry.value_ptr.*;

            const resource_type = resource_value.object.get("type").?.string;
            //
            // var found = false;
            // inline for(std.meta.eql(resource_type, ))

            std.debug.print("Resource Name: {s}, Type: {}\n", .{ resource_name, resource_type });
        }
    }
};

test "State map parsing" {
    const allocator = std.testing.allocator;
    var state = State.init(allocator);
    defer state.deinit();

    const json =
        \\{
        \\  "setup-shell": {
        \\    "type": "file",
        \\    "path": "/home/user/.zshrc",
        \\    "content": "alias z=zig"
        \\  },
        \\  "compiler": {
        \\    "type": "package",
        \\    "name": "zig"
        \\  }
        \\}
    ;

    try state.load(json);
}
