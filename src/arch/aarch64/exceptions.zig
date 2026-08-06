const cpu = @import("cpu.zig");
const memory = @import("memory.zig");

const console = @import("../../console.zig");

pub const ExceptionFrame = extern struct {
    x: [31]cpu.Register,

    sp: memory.PhsycialAddress,
    elr_el1: memory.PhsycialAddress,
    spsr_el1: memory.PhsycialAddress,
    esr_el1: memory.PhsycialAddress,
    far_el1: memory.PhsycialAddress,
};

fn exceptionHandler(frame: *const ExceptionFrame) callconv(.c) void {
    for (frame.x, 0..) |x, i| {
        if (i % 2 == 1) {
            console.println("x[{d}]=0x{x}", .{ i, x });
        } else {
            console.print("x[{d}]=0x{x}", .{ i, x });
        }
    }

    console.println("sp={x}", .{frame.sp});
    console.println("elr_el1={x}", .{frame.elr_el1});
    console.println("spsr_el1={x}", .{frame.spsr_el1});
    console.println("esr_el1={x}", .{frame.esr_el1});
    console.println("far_el1={x}", .{frame.far_el1});
}
