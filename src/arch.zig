const builtin = @import("builtin");

pub const arch = switch (builtin.cpu.arch) {
    .aarch64 => @import("arch/aarch64.zig"),
    else => @compileError("unsupported cpu architecture"),
};

pub const assembly = arch.assembly;
pub const cpu = arch.cpu;
pub const exceptions = arch.exceptions;
pub const memory = arch.memory;
