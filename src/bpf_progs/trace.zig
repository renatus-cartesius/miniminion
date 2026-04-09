const std = @import("std");
const BPF = std.os.linux.BPF;

export const _license linksection("license") = "GPL".*;

export fn trace_execve(ctx: *anyopaque) linksection("tracepoint/syscalls/sys_enter_execve") c_int {
    _ = ctx;
    const pid = BPF.kern.helpers.get_current_pid_tgid() >> 32;
    const fmt = "execve called by PID: %d\n";
    _ = BPF.kern.helpers.trace_printk(fmt, fmt.len, pid, 0, 0);
    return 0;
}
