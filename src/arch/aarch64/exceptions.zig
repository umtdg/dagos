const cpu = @import("cpu.zig");
const memory = @import("memory.zig");

const console = @import("../../console.zig");

pub const ExceptionFrame = extern struct {
    x: [31]cpu.Register,

    sp: cpu.Register,
    elr_el1: cpu.Register,
    spsr_el1: cpu.Register,
    esr_el1: cpu.Register,
    far_el1: cpu.Register,
};

export fn exceptionHandler(frame: *const ExceptionFrame) callconv(.c) void {
    for (frame.x, 0..) |x, i| {
        if (i % 2 == 1) {
            console.println("x[{d}]=0x{x:016}", .{ i, x });
        } else {
            console.print("x[{d}]=0x{x:016} ", .{ i, x });
        }
    }

    console.println("sp=0x{x:016}", .{frame.sp});
    console.println("elr_el1=0x{x:016}", .{frame.elr_el1});
    console.println("spsr_el1=0x{x:016}", .{frame.spsr_el1});
    console.println("esr_el1=0x{x:016}", .{frame.esr_el1});
    console.println("far_el1=0x{x:016}", .{frame.far_el1});
}
