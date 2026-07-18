const std = @import("std");
const Controller = @import("controller/Controller.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var controller = Controller.create(init);

    const manifest_path = if (args.len > 1) args[1] else "minim.jsonnet";
    const port: u16 = if (args.len > 2) try std.fmt.parseInt(u16, args[2], 10) else 9876;

    try controller.run(manifest_path, port);
}