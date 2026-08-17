const arch = @import("arch.zig");

pub extern fn switchContext(
    prev_sp: *arch.memory.VirtualAddress,
    next_sp: *const arch.memory.VirtualAddress,
) callconv(.c) void;

pub const MAX = 8;
pub const STACK_SIZE = 8192;

var processes: [MAX]Process = undefined;

pub const State = enum(u8) {
    Unused,
    Runnable,
};

pub const Process = struct {
    pid: u32,
    state: State,
    sp: arch.memory.VirtualAddress,
    stack: [STACK_SIZE]u8 align(arch.cpu.STACK_ALIGNMENT),

    pub fn spawn(pc: arch.memory.VirtualAddress) *Process {
        const process: *Process = blk: for (&processes, 0..) |*p, i| {
            if (p.state == .Unused) {
                p.pid = @intCast(i + 1);
                break :blk p;
            }
        } else @panic("Maximum number of processes reached");

        const stack: [*]u8 = &process.stack;
        var sp: [*]arch.cpu.Register = @ptrCast(@alignCast(stack + process.stack.len));

        sp -= 12;
        @memset(sp[0..12], 0);
        sp[11] = pc;

        process.state = .Runnable;
        process.sp = @intFromPtr(sp);
        return process;
    }
};
