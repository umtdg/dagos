const std = @import("std");
const builtin = std.builtin;

const arch = @import("arch.zig");
const console = @import("console.zig");
const memory = @import("memory.zig");
const platform = @import("platform.zig");
const process = @import("process.zig");

comptime {
    _ = arch.exceptions;
}

extern var __bss: [0]u8;
extern var __bss_end: [0]u8;

extern var __kernel_end: [0]u8;

pub const panic = std.debug.FullPanic(panicHandler);
fn panicHandler(msg: []const u8, first_trace_addr: ?usize) noreturn {
    _ = first_trace_addr;
    console.print("KERNEL PANIC: {s}\n", .{msg});

    arch.cpu.halt();
}

fn delay() void {
    for (0..30000000) |_| {
        arch.assembly.nop();
    }
}

fn procAEntry() void {
    console.println("starting process A", .{});
    while (true) {
        console.print("A", .{});
        process.yield();
        delay();
    }
}

fn procBEntry() void {
    console.println("starting process B", .{});
    while (true) {
        console.print("B", .{});
        process.yield();
        delay();
    }
}

export fn kmain() callconv(.c) noreturn {
    platform.init();

    var page_allocator = memory.PageAllocator.init(
        &platform.physicalMemory(),
        @intFromPtr(&__kernel_end),
        0x1000, // 4096
    );

    process.init();

    const paddr0 = page_allocator.allocPages(2);
    const paddr1 = page_allocator.allocPages(1);
    console.print("paddr0={d}\n", .{paddr0});
    console.print("paddr1={d}\n", .{paddr1});

    _ = process.Process.spawn(@intFromPtr(&procAEntry));
    _ = process.Process.spawn(@intFromPtr(&procBEntry));

    process.yield();
    @panic("Switched to idle process");
}
