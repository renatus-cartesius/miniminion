const std = @import("std");
const BPF = std.os.linux.BPF;

export const _license linksection("license") = "GPL".*;

const BPF_MAP_TYPE_ARRAY = 2;

export var pkt_counter linksection(".maps") = BPF.kern.MapDef{
    .type = BPF_MAP_TYPE_ARRAY,
    .key_size = @sizeOf(u32),
    .value_size = @sizeOf(u64),
    .max_entries = 1024,
    .map_flags = 0,
};

export fn count_packets(ctx: *BPF.kern.XdpMd) linksection("xdp") c_int {
    _ = ctx;
    const key: u32 = 0;

    if (BPF.kern.helpers.map_lookup_elem(&pkt_counter, &key)) |ptr| {
        const val: *u64 = @ptrCast(@alignCast(ptr));
        _ = @atomicRmw(u64, val, 1, .Add, .seq_cst);
    }

    return 2;
}
