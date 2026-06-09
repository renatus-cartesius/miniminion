#include "vmlinux.h"
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

const char target[] = "foobar";

#define MAX_PATH_LEN 4096
#define MAX_DEPTH 128
#define NAME_MAX 32

struct {
  __uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
  __uint(max_entries, 1);
  __type(key, u32);
  __type(value, char[MAX_PATH_LEN]);
} path_heap SEC(".maps");

SEC("fexit/vfs_open")
int BPF_PROG(trace_foobar_change, const struct path *path, struct file *file,
             int ret) {

  char filename_buf[NAME_MAX];
  const char *fname_ptr = BPF_CORE_READ(path, dentry, d_name.name);
  int flen =
      bpf_probe_read_kernel_str(filename_buf, sizeof(filename_buf), fname_ptr);
  if (flen <= 1)
    return 0;
  if (bpf_strncmp(filename_buf, sizeof(target), target) != 0)
    return 0;

  u32 zero = 0;
  char *buf = bpf_map_lookup_elem(&path_heap, &zero);
  if (!buf)
    return 0;

  int pos = MAX_PATH_LEN - 1;
  buf[pos] = '\0';

  struct dentry *dent = BPF_CORE_READ(path, dentry);
  struct dentry *parent;

  for (int i = 0; i < MAX_DEPTH; i++) {
    parent = BPF_CORE_READ(dent, d_parent);
    if (dent == parent)
      break;

    char name[NAME_MAX];
    const char *name_ptr = BPF_CORE_READ(dent, d_name.name);
    int len = bpf_probe_read_kernel_str(name, sizeof(name), name_ptr);
    if (len <= 1)
      break;
    len--;

    pos -= len;
    if (pos < 1 || pos >= MAX_PATH_LEN)
      break;

    bpf_probe_read_kernel(buf + (pos & (MAX_PATH_LEN - 1)), len, name);

    pos -= 1;
    if (pos < 0 || pos >= MAX_PATH_LEN)
      break;
    buf[pos & (MAX_PATH_LEN - 1)] = '/';

    dent = parent;
  }

  if (pos < 0 || pos >= MAX_PATH_LEN)
    return 0;

  pos &= (MAX_PATH_LEN - 1);
  char fmt[] = "path: %s\n";
  bpf_trace_printk(fmt, sizeof(fmt), buf + pos);

  return 0;
}

char _license[] SEC("license") = "GPL";
