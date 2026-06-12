#include "vmlinux.h"
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

#define NAME_MAX 32
#define MAX_DEPTH 20

struct trie_key {
  u32 parent_node_id;
  char name[NAME_MAX];
};

struct trie_value {
  u32 next_node_id;
  u8 is_terminal;
};

struct {
  __uint(type, BPF_MAP_TYPE_HASH);
  __uint(max_entries, 4096);
  __type(key, struct trie_key);
  __type(value, struct trie_value);
} path_trie_map SEC(".maps");

SEC("fexit/vfs_write")
int BPF_PROG(trace_foobar_change, struct file *file, const char *buf,
             size_t count, loff_t *pos, ssize_t ret) {
  if (ret <= 0 || !file)
    return 0;

  struct dentry *dent = BPF_CORE_READ(file, f_path.dentry);
  struct dentry *parent;

  u32 current_parent_id = 0;
  char name_buf[NAME_MAX];

#pragma unroll
  for (int i = 0; i < MAX_DEPTH; i++) {
    if (!dent)
      break;

    parent = BPF_CORE_READ(dent, d_parent);
    if (dent == parent)
      break;

    const char *name_ptr = BPF_CORE_READ(dent, d_name.name);
    if (!name_ptr)
      break;

    __builtin_memset(name_buf, 0, sizeof(name_buf));
    bpf_probe_read_kernel_str(name_buf, sizeof(name_buf), name_ptr);

    struct trie_key key = {
        .parent_node_id = current_parent_id,
    };
    __builtin_memcpy(key.name, name_buf, NAME_MAX);

    struct trie_value *val = bpf_map_lookup_elem(&path_trie_map, &key);

    if (!val) {
      return 0;
    }

    if (val->is_terminal) {
      if (BPF_CORE_READ(parent, d_parent) == parent) {
        char fmt[] = "ALERT: Drift detected via Trie Step-by-Step Match!\n";
        bpf_trace_printk(fmt, sizeof(fmt));
        return 0;
      }
    }

    current_parent_id = val->next_node_id;
    dent = parent;
  }

  return 0;
}

char _license[] SEC("license") = "GPL";
