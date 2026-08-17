const arch = @import("arch.zig");

pub const MAX_PROCESS_COUNT = 8;
pub const PROCESS_STACK_SIZE = 8192;

var processes: [MAX_PROCESS_COUNT]Process = undefined;
var current_process: *Process = undefined;
var idle_process: *Process = undefined;

pub const ProcessState = enum {
    Unused,
    Runnable,
};

pub const Process = struct {
    pid: u32,
    state: ProcessState,
    sp: arch.memory.VirtualAddress,
    stack: [PROCESS_STACK_SIZE]u8 align(arch.cpu.STACK_ALIGNMENT),

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

pub fn init() void {
    for (&processes) |*p| {
        p.state = .Unused;
    }

    idle_process = Process.spawn(0);
    idle_process.pid = 0;
    current_process = idle_process;
}

pub fn yield() void {
    var next_process: *Process = blk: for (0..MAX_PROCESS_COUNT) |i| {
        const p: *Process = &processes[(current_process.pid + i) % MAX_PROCESS_COUNT];
        if (p.state == .Runnable and p.pid > 0) {
            break :blk p;
        }
    } else return;

    const prev_process: *Process = current_process;
    current_process = next_process;
    arch.context.switchContext(&prev_process.sp, &next_process.sp);
}
