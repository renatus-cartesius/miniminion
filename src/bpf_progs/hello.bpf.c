#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>

char LICENSE[] SEC("license") = "GPL";

SEC("tracepoint/syscalls/sys_enter_execve")
int hello_world(void *ctx) {
    char msg[] = "Hello from Zig-loaded BPF!\n";
    bpf_trace_printk(msg, sizeof(msg));
    return 0;
}
