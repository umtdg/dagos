const arch = @import("../arch.zig");
const PhsycialAddress = arch.memory.PhsycialAddress;
const VirtualAddress = arch.memory.VirtualAddress;

pub const Pl011 = struct {
    base: VirtualAddress,

    const DR_OFFSET = 0x00;
    const FR_OFFSET = 0x18;

    const FR_TXFF: u32 = 1 << 5;

    pub fn init(base: VirtualAddress) Pl011 {
        return .{ .base = base };
    }

    pub inline fn dr(self: *const Pl011) *volatile u32 {
        return @ptrFromInt(self.base + DR_OFFSET);
    }

    pub inline fn fr(self: *const Pl011) *volatile u32 {
        return @ptrFromInt(self.base + FR_OFFSET);
    }

    pub inline fn writeByte(self: *const Pl011, byte: u8) void {
        while (self.fr().* & FR_TXFF != 0) {
            arch.assembly.wfe();
        }

        self.dr().* = @intCast(byte);
    }

    pub inline fn write(self: *const Pl011, bytes: []const u8) void {
        for (bytes) |byte| {
            self.writeByte(byte);
        }
    }
};
