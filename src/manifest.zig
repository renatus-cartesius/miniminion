const std = @import("std");
const cmd = @import("modules/utils/cmd.zig");
const c = @cImport({
    @cInclude("libjsonnet.h");
});

const CallbackCtx = struct {
    vm: *c.JsonnetVm,
    io: std.Io,
    allocator: std.mem.Allocator,
};

pub const Manifest = struct {
    json_output: []const u8,

    pub fn load(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8) !Manifest {
        const vm = c.jsonnet_make() orelse return error.JsonnetVmMakeError;
        defer c.jsonnet_destroy(vm);

        var ctx = CallbackCtx{ .vm = vm, .io = io, .allocator = allocator };
        const params = [_:null]?[*:0]const u8{ "cmd", null };
        c.jsonnet_native_callback(vm, "shellExec", shellExec, &ctx, @ptrCast(&params));

        var file = try std.Io.Dir.openFile(std.Io.Dir.cwd(), io, file_path, .{});
        defer file.close(io);
        const buf = try allocator.alloc(u8, 1024 * 1024);
        defer allocator.free(buf);
        var reader = file.reader(io, buf);
        const content = try reader.interface.readAlloc(allocator, try file.length(io));
        defer allocator.free(content);

        var error_found: i32 = 0;
        var ts_start: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(.MONOTONIC, &ts_start);
        const result_ptr = c.jsonnet_evaluate_snippet(vm, &file_path[0], &content[0], &error_found);
        var ts_end: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(.MONOTONIC, &ts_end);
        const elapsed_ns = (@as(i128, ts_end.sec) - @as(i128, ts_start.sec)) * std.time.ns_per_s + (@as(i128, ts_end.nsec) - @as(i128, ts_start.nsec));
        const elapsed_ms: f64 = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, std.time.ns_per_ms);
        std.debug.print("Jsonnet evaluation took {d:.2}ms\n", .{elapsed_ms});

        if (error_found != 0) {
            if (result_ptr) |ptr| {
                const err_msg = std.mem.span(ptr);
                std.debug.print("Jsonnet eval error:\n{s}\n", .{err_msg});
            }
            return error.JsonnetEvalError;
        }

        if (result_ptr) |ptr| {
            defer _ = c.jsonnet_realloc(vm, ptr, 0);
            const json_output = try allocator.dupe(u8, std.mem.span(ptr));
            return Manifest{ .json_output = json_output };
        }

        return error.JsonnetEvalError;
    }

    fn shellExec(
        ctx: ?*anyopaque,
        argv: [*c]const ?*const c.JsonnetJsonValue,
        success: [*c]c_int,
    ) callconv(.c) ?*c.JsonnetJsonValue {
        const cbctx: *CallbackCtx = @ptrCast(@alignCast(ctx));

        const shell_cmd_json = argv[0] orelse {
            success.* = 0;
            return makeString(cbctx.vm, "missing cmd argument");
        };

        const shell_cmd = c.jsonnet_json_extract_string(cbctx.vm, shell_cmd_json) orelse {
            success.* = 0;
            return makeString(cbctx.vm, "argument must be a string");
        };

        const cmd_argv = [_][]const u8{ "sh", "-c", std.mem.span(shell_cmd) };
        const res = cmd.run(cbctx.allocator, cbctx.io, &cmd_argv) catch {
            success.* = 0;
            return makeString(cbctx.vm, "error on running shell");
        };
        defer {
            cbctx.allocator.free(res.stdout);
            cbctx.allocator.free(res.stderr);
        }

        if (res.term == .exited and res.term.exited != 0) {
            success.* = 0;

            const msg = std.fmt.allocPrintSentinel(
                cbctx.allocator,
                "native shell exec failed with error: \n{s}",
                .{res.stderr},
                0,
            ) catch {
                return makeString(cbctx.vm, "failed to format shell exec error message");
            };
            defer cbctx.allocator.free(msg);

            return makeString(cbctx.vm, msg);
        }

        const trimmed = std.mem.trimEnd(u8, res.stdout, "\n");
        const trimmed_z = cbctx.allocator.dupeSentinel(u8, trimmed, 0) catch {
            success.* = 0;
            return makeString(cbctx.vm, "alloc failed");
        };
        defer cbctx.allocator.free(trimmed_z);

        success.* = 1;
        return makeString(cbctx.vm, trimmed_z);
    }
};

fn makeString(vm: *c.JsonnetVm, s: [*:0]const u8) *c.JsonnetJsonValue {
    const res = c.jsonnet_json_make_string(vm, s).?;
    return res;
}
