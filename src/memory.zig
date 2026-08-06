const std = @import("std");

const arch = @import("arch.zig").arch;
const PhysicalAddress = arch.memory.PhsycialAddress;

pub fn asPtr(comptime Address: type, comptime Pointer: type, address: Address) Pointer {
    return @ptrFromInt(address);
}

pub const MemoryRegion = struct {
    start: PhysicalAddress,
    size: u64,
};

pub const PageAllocator = struct {
    next: PhysicalAddress,
    end: PhysicalAddress,
    page_size: u64,

    pub fn init(
        region: *const MemoryRegion,
        kernel_end: PhysicalAddress,
        page_size: PhysicalAddress,
    ) PageAllocator {
        const region_end = region.start + region.size;
        const next = std.mem.alignForward(PhysicalAddress, kernel_end, page_size);

        if (next < region.start or next > region_end) {
            @panic("page_allocator: start address overflow");
        }

        return PageAllocator{
            .next = next,
            .end = region_end,
            .page_size = page_size,
        };
    }

    pub fn allocPages(self: *PageAllocator, count: usize) PhysicalAddress {
        const size = count * self.page_size;
        const page_addr = self.next;
        self.next += size;

        if (self.next > self.end) {
            @panic("OOM");
        }

        const page_ptr: [*]u8 = asPtr(PhysicalAddress, [*]u8, page_addr);
        const page: []u8 = page_ptr[0..size];
        @memset(page, 0);
        return page_addr;
    }
};
