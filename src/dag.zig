const std = @import("std");

pub fn DAG(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        nodes: std.ArrayList(Node),

        pub const Node = struct {
            value: T,
            dependencies: std.ArrayList(usize),
        };

        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{
                .allocator = allocator,
                .nodes = try std.ArrayList(Node).initCapacity(allocator, 0),
            };
        }

        pub fn addNode(self: *Self, v: T) !usize {
            const node = Node{
                .value = v,
                .dependencies = try std.ArrayList(usize).initCapacity(self.allocator, 0),
            };
            try self.nodes.append(self.allocator, node);
            return self.nodes.items.len - 1;
        }

        pub fn addEdge(self: *Self, from_idx: usize, to_idx: usize) !void {
            try self.nodes.items[to_idx].dependencies.append(self.allocator, from_idx);
        }

        pub fn deinit(self: *Self) void {
            for (self.nodes.items) |*node| {
                node.dependencies.deinit(self.allocator);
            }
            self.nodes.deinit(self.allocator);
        }

        pub fn topologicalSort(self: *Self, allocator: std.mem.Allocator) ![]usize {
            const node_count = self.nodes.items.len;
            var result = try std.ArrayList(usize).initCapacity(allocator, node_count);
            errdefer result.deinit(self.allocator);

            var in_degree = try allocator.alloc(usize, node_count);
            defer allocator.free(in_degree);
            @memset(in_degree, 0);

            for (self.nodes.items) |node| {
                for (node.dependencies.items) |dep_idx| {
                    in_degree[dep_idx] += 1;
                }
            }

            var queue = try std.ArrayList(usize).initCapacity(allocator, node_count);
            defer queue.deinit(self.allocator);

            for (in_degree, 0..) |degree, i| {
                if (degree == 0) try queue.append(self.allocator, i);
            }

            var head: usize = 0;
            while (head < queue.items.len) {
                const u = queue.items[head];
                head += 1;
                try result.append(self.allocator, u);

                for (self.nodes.items[u].dependencies.items) |v| {
                    in_degree[v] -= 1;
                    if (in_degree[v] == 0) {
                        try queue.append(self.allocator, v);
                    }
                }
            }

            if (result.items.len < node_count) {
                return error.CycleDetected;
            }

            return result.toOwnedSlice(self.allocator);
        }
    };
}

test "DAG: common case" {
    const allocator = std.testing.allocator;
    var dag = try DAG(i32).init(allocator);
    defer dag.deinit();

    const task_a = try dag.addNode(101);
    const task_b = try dag.addNode(102);
    const task_c = try dag.addNode(103);

    try dag.addEdge(task_a, task_c);
    try dag.addEdge(task_b, task_c);

    try std.testing.expectEqual(@as(usize, 3), dag.nodes.items.len);

    const node_c = dag.nodes.items[task_c];
    try std.testing.expectEqual(@as(usize, 2), node_c.dependencies.items.len);

    try std.testing.expectEqual(task_a, node_c.dependencies.items[0]);
    try std.testing.expectEqual(task_b, node_c.dependencies.items[1]);
}

test "DAG: empty graph" {
    const allocator = std.testing.allocator;
    var dag = try DAG(i32).init(allocator);
    defer dag.deinit();

    try std.testing.expectEqual(@as(usize, 0), dag.nodes.items.len);
}

test "DAG: topological sort" {
    const allocator = std.testing.allocator;
    var dag = try DAG(i32).init(allocator);
    defer dag.deinit();

    const a = try dag.addNode(1);
    const b = try dag.addNode(2);
    const c = try dag.addNode(3);

    try dag.addEdge(c, b);
    try dag.addEdge(b, a);

    const order = try dag.topologicalSort(allocator);
    defer allocator.free(order);

    try std.testing.expectEqual(@as(usize, 0), order[0]);
    try std.testing.expectEqual(@as(usize, 1), order[1]);
    try std.testing.expectEqual(@as(usize, 2), order[2]);
}

test "DAG: simple state execution" {
    const print = std.debug.print;
    const allocator = std.testing.allocator;
    var dag = try DAG([]const u8).init(allocator);
    defer dag.deinit();

    const app = try dag.addNode("Application");
    const systemd = try dag.addNode("Systemd service");
    const config = try dag.addNode("Config file");
    const db = try dag.addNode("Database");

    try dag.addEdge(app, systemd);
    try dag.addEdge(systemd, config);
    try dag.addEdge(app, db);
    try dag.addEdge(db, systemd);

    const order = try dag.topologicalSort(allocator);
    defer allocator.free(order);

    try std.testing.expectEqual(config, order[0]);
    try std.testing.expectEqual(systemd, order[1]);
    try std.testing.expectEqual(db, order[2]);
    try std.testing.expectEqual(app, order[3]);

    print("\nDag test sequence:\n", .{});
    for (order) |i| {
        print("{s} -> ", .{dag.nodes.items[i].value});
    }
    print("Done.\n", .{});
}
