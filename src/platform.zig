const config = @import("config");

const platform = switch (config.platform) {
    .virt => @import("platform/virt.zig"),
    .raspi3b => @import("platform/raspi3b.zig"),
    .raspi4b => @import("platform/raspi4b.zig"),
    .raspi5b => @import("platform/raspi5b.zig"),
};

pub const init = platform.init;
pub const console = platform.console;
pub const physicalMemory = platform.physicalMemory;
