const memory = @import("memory.zig");

pub extern fn switchContext(
    prev_sp: *memory.VirtualAddress,
    next_sp: *const memory.VirtualAddress,
) callconv(.c) void;
