#include "vmlinux.h"
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

const char target[] = "foobar";

SEC("fexit/vfs_write")
int BPF_PROG(trace_foobar_change, struct file *file, const char *buf,
             size_t count, loff_t *pos, ssize_t ret) {

  char filename_buf[32];
  const char *filename_ptr = BPF_CORE_READ(file, f_path.dentry, d_name.name);
  long res = bpf_probe_read_kernel_str(filename_buf, sizeof(filename_buf),
                                       filename_ptr);

  if (res <= 0)
    return 0;

  if (bpf_strncmp(filename_buf, sizeof(target), target) == 0) {
    if (ret > 0) {
      bpf_printk("FOOBAR CHANGED, count: %d!", ret);
    }
  }

  return 0;
}

char _license[] SEC("license") = "GPL";
