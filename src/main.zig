const std = @import("std");
const state_manager = @import("state_manager.zig");

pub fn main(init: std.process.Init) !void {
    var sm = state_manager{};
    try sm.run(init, "minim.jsonnet");
}