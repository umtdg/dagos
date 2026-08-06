pub inline fn nop() void {
    asm volatile ("nop");
}

pub inline fn wfe() void {
    asm volatile ("wfe");
}

pub inline fn udf(imm: comptime_int) void {
    asm volatile (
        \\ udf #{imm}
        :
        : [imm] "{imm}" (imm),
    );
}
