const std = @import("std");
const dag = @import("dag.zig");

pub const AgentNode = struct {
    hostname: []const u8,
    state_file: []const u8,
    state_content: []const u8,
};

pub const Stack = struct {
    dag: dag.DAG(AgentNode),
    hostname_to_idx: std.StringHashMap(usize),

    pub fn deinit(self: *Stack) void {
        self.dag.deinit();
        self.hostname_to_idx.deinit();
    }

    pub fn dependenciesFor(self: *Stack, hostname: []const u8) ?[]const usize {
        const idx = self.hostname_to_idx.get(hostname) orelse return null;
        return self.dag.nodes.items[idx].dependencies.items;
    }

    pub fn agentNode(self: *Stack, hostname: []const u8) ?AgentNode {
        const idx = self.hostname_to_idx.get(hostname) orelse return null;
        return self.dag.nodes.items[idx].value;
    }
};

pub fn parse(allocator: std.mem.Allocator, io: std.Io, stack_json: []const u8, base_dir: []const u8) !Stack {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, stack_json, .{});
    defer parsed.deinit();

    var sdag = try dag.DAG(AgentNode).init(allocator);
    var hostname_to_idx = std.StringHashMap(usize).init(allocator);

    const agents = parsed.value.object.get("agents") orelse return error.MissingAgentsField;
    var agent_iter = agents.object.iterator();

    while (agent_iter.next()) |entry| {
        const hostname = entry.key_ptr.*;
        const agent_data = entry.value_ptr.*;

        const state_file = agent_data.object.get("state") orelse return error.MissingStateField;
        const state_file_path = if (base_dir.len > 0)
            try std.fs.path.join(allocator, &.{ base_dir, state_file.string })
        else
            try allocator.dupe(u8, state_file.string);

        const file = try std.Io.Dir.openFile(std.Io.Dir.cwd(), io, state_file_path, .{});
        defer file.close(io);

        var read_buf: [1024 * 1024]u8 = undefined;
        var file_reader = file.reader(io, &read_buf);
        const state_content = try file_reader.interface.readAlloc(allocator, try file.length(io));

        const idx = try sdag.addNode(.{
            .hostname = try allocator.dupe(u8, hostname),
            .state_file = try allocator.dupe(u8, state_file.string),
            .state_content = state_content,
        });
        try hostname_to_idx.put(hostname, idx);
    }

    var dep_iter = agents.object.iterator();
    while (dep_iter.next()) |entry| {
        const hostname = entry.key_ptr.*;
        const agent_data = entry.value_ptr.*;

        const from_idx = hostname_to_idx.get(hostname) orelse return error.UnknownHostname;
        if (agent_data.object.get("depends")) |depends| {
            for (depends.array.items) |dep| {
                const to_idx = hostname_to_idx.get(dep.string) orelse return error.UnknownHostname;
                try sdag.addEdge(to_idx, from_idx);
            }
        }
    }

    return Stack{
        .dag = sdag,
        .hostname_to_idx = hostname_to_idx,
    };
}