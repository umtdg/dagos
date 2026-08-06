const uart = @import("uart.zig");

pub const ExceptionFrame = extern struct {
    x: [31]u64,

    sp: u64,
    elr_el1: u64,
    spsr_el1: u64,
    esr_el1: u64,
    far_el1: u64,
};

comptime {
    // assert ExceptionFrame is 288 bytes
    if (@sizeOf(ExceptionFrame) != 0x120) {
        @compileError("ExceptionFrame is not of expected size of 288 bytes");
    }
}

export fn exceptionHandler(frame: *const ExceptionFrame) callconv(.c) void {
    uart.putchar('\n');

    for (frame.x, 0..) |reg, i| {
        uart.puts("x[");
        uart.putDec64(i);
        uart.puts("]=");
        uart.putHex64(reg);
        if (i % 2 == 1) {
            uart.putchar('\n');
        } else {
            uart.putchar(' ');
        }
    }

    uart.puts("sp=");
    uart.putHex64(frame.sp);
    uart.putchar('\n');

    uart.puts("elr_el1=");
    uart.putHex64(frame.elr_el1);
    uart.putchar('\n');

    uart.puts("spsr_el1=");
    uart.putHex64(frame.spsr_el1);
    uart.putchar('\n');

    uart.puts("esr_el1=");
    uart.putHex64(frame.esr_el1);
    uart.putchar('\n');

    uart.puts("far_el1=");
    uart.putHex64(frame.far_el1);
    uart.putchar('\n');

    // hang happens after this in entry.S
}
