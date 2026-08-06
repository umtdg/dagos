const config = @import("config");

pub const Platform = enum {
    qemu_virt,
};

const platform = switch (config.platform) {
    .qemu_virt => @import("platform/qemu_virt.zig"),
};

pub const init = platform.init;
pub const console = platform.console;
pub const physicalMemory = platform.physicalMemory;
