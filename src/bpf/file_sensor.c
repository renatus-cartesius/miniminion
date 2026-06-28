#define __BPF_SENSOR__

#include "file_sensor.h"
#include "vmlinux.h"
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

struct {
  __uint(type, BPF_MAP_TYPE_RINGBUF);
  __uint(max_entries, 256 * 1024);
} write_rb SEC(".maps");

struct path_buf {
  char data[PATH_BUF_SIZE];
};

struct {
  __uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
  __type(key, u32);
  __type(value, struct path_buf);
  __uint(max_entries, 1);
} path_heap SEC(".maps");

struct trie_key {
  u32 parent_node_id;
  u64 mnt_id;
  char name[NAME_MAX];
};

struct trie_value {
  u32 next_node_id;
  u64 mnt_id;
  u8 is_terminal;
};

struct {
  __uint(type, BPF_MAP_TYPE_HASH);
  __uint(max_entries, 4096);
  __type(key, struct trie_key);
  __type(value, struct trie_value);
} path_trie_map SEC(".maps");

SEC("fexit/vfs_write")
int BPF_PROG(file_sensor, struct file *file, const char *buf, size_t count,
             loff_t *pos, ssize_t ret) {
  if (ret <= 0 || !file)
    return 0;

  u32 zero = 0;
  struct path_buf *pb = bpf_map_lookup_elem(&path_heap, &zero);
  if (!pb)
    return 0;

  __builtin_memset(pb->data, 0, PATH_BUF_SIZE);
  u32 path_offset = 0;

  struct dentry *dent = BPF_CORE_READ(file, f_path.dentry);
  struct dentry *parent;
  u32 current_parent_id = 0;
  char name_buf[NAME_MAX];

  struct mount *m =
      container_of(BPF_CORE_READ(file, f_path.mnt), struct mount, mnt);
  u64 mnt_id = BPF_CORE_READ(m, mnt_id);

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
    int name_len =
        bpf_probe_read_kernel_str(name_buf, sizeof(name_buf), name_ptr);

    struct trie_key key = {
        .parent_node_id = current_parent_id,
        .mnt_id = mnt_id,
    };
    __builtin_memcpy(key.name, name_buf, NAME_MAX);

    if (path_offset + 1 + NAME_MAX < PATH_BUF_SIZE) {

      if (path_offset >= PATH_BUF_SIZE)
        break;

      pb->data[path_offset] = '/';
      path_offset += 1;

      // if (path_offset + NAME_MAX > PATH_BUF_SIZE)
      //   break;
      __builtin_memcpy(pb->data + (path_offset & 255), name_buf, NAME_MAX);
      path_offset += (name_len > 1 ? name_len - 1 : 0); // name_len includes
    }

    struct trie_value *val = bpf_map_lookup_elem(&path_trie_map, &key);
    if (!val)
      return 0;

    if (val->is_terminal) {

      // pushing event to ringbuf
      struct write_event *e;

      e = bpf_ringbuf_reserve(&write_rb, sizeof(*e), 0);
      if (!e)
        return 0;
      e->mnt_id = mnt_id;
      __builtin_memcpy(e->path, pb->data, PATH_BUF_SIZE);
      bpf_ringbuf_submit(e, 0);

      bpf_printk("DEBUG=wrote: mountid=%d, file=%s\n", mnt_id, pb->data);
      return 0;
    }

    current_parent_id = val->next_node_id;
    dent = parent;
  }

  return 0;
}

char _license[] SEC("license") = "GPL";
