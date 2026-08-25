const std = @import("std");
const Controller = @import("controller/Controller.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    const stack_path = if (args.len > 1) args[1] else "stack.jsonnet";
    const port: u16 = if (args.len > 2) try std.fmt.parseInt(u16, args[2], 10) else 8080;
    const etcd_host = if (args.len > 3) args[3] else "127.0.0.1";
    const etcd_port: u16 = if (args.len > 4) try std.fmt.parseInt(u16, args[4], 10) else 2379;

    var controller = Controller.create(init, etcd_host, etcd_port);
    try controller.run(stack_path, port);
}