const std = @import("std");
const state_manager = @import("state_manager.zig");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const manifest_path = if (args.len > 1) args[1] else "minim.jsonnet";

    var sm = state_manager{};
    try sm.run(init, manifest_path);
}