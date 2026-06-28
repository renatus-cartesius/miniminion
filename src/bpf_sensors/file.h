#pragma once

#ifdef __BPF_SENSOR__
#include "vmlinux.h"
#else
#include <stdint.h>
typedef uint64_t u64;
#endif

#define NAME_MAX 32
#define MAX_DEPTH 20
#define PATH_BUF_SIZE (NAME_MAX * MAX_DEPTH + MAX_DEPTH + 1)

struct write_event {
  u64 mnt_id;
  char path[PATH_BUF_SIZE];
};
