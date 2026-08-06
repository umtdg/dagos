const _asm = @import("asm.zig");

pub const Register: type = u64;

pub inline fn halt() noreturn {
    while (true) {
        _asm.wfe();
    }
}
