const std = @import("std");
const Agent = @import("agent/Agent.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    if (args.len > 2 and std.mem.eql(u8, args[1], "--controller")) {
        const host_port = args[2];
        const colon = std.mem.indexOfScalar(u8, host_port, ':') orelse return error.InvalidHostPort;
        var agent = Agent.create(init, host_port);
        try agent.runFromController(host_port[0..colon], try std.fmt.parseInt(u16, host_port[colon + 1 ..], 10));
    } else {
        var agent = Agent.create(init, "");
        const manifest_path = if (args.len > 1) args[1] else "minim.jsonnet";
        try agent.run(manifest_path);
    }
}