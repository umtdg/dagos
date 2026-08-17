const arch = @import("../arch.zig").arch;
const PhysicalAddress = arch.memory.PhysicalAddress;

const drivers = @import("../drivers.zig");
const memory = @import("../memory.zig");

const UART_BASE: PhysicalAddress = 0x09000000;

const PHYSICAL_MEMORY: memory.MemoryRegion = .{
    .start = 0x40000000,
    .size = 128 * 1024 * 1024, // 128 MiB
};

const uart0 = drivers.uart.Pl011.init(UART_BASE);

pub fn init() void {
    // QEMU exposes PL011 in a usable state
}

pub fn console() *const drivers.uart.Pl011 {
    return &uart0;
}

pub fn physicalMemory() memory.MemoryRegion {
    return PHYSICAL_MEMORY;
}
