const std = @import("std");
const Platform = @import("src/platform.zig").Platform;

pub fn build(b: *std.Build) void {
    const Target = std.Target.aarch64;
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .freestanding,
        .cpu_model = .{ .explicit = &Target.cpu.generic },
        .cpu_features_add = Target.featureSet(&.{.strict_align}),
        .cpu_features_sub = Target.featureSet(&.{ .fp_armv8, .neon }),
    });
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });

    // platform build option
    const platform: Platform = b.option(Platform, "platform", "Target platform") orelse .qemu_virt;

    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .stack_protector = false,
    });

    switch (target.result.cpu.arch) {
        .aarch64 => {
            kernel_mod.addCSourceFiles(.{
                .files = &.{
                    "src/arch/aarch64/entry.S",
                    "src/arch/aarch64/exceptions.S",
                    "src/arch/aarch64/context.S",
                },
                .flags = &.{ "-x", "assembler-with-cpp" },
            });
        },
        else => @panic("unsupported cpu architecture"),
    }

    // add options
    const options = b.addOptions();
    options.addOption(Platform, "platform", platform);
    kernel_mod.addOptions("config", options);

    const kernel = b.addExecutable(.{
        .name = "dagos.elf",
        .root_module = kernel_mod,
        .use_lld = true,
    });

    switch (platform) {
        .qemu_virt => {
            kernel.setLinkerScript(b.path("src/linker/qemu-virt.ld"));
        },
    }
    b.installArtifact(kernel);

    const qemu = b.addSystemCommand(&.{
        // zig fmt: off
        "qemu-system-aarch64",
        "-machine", "virt",
        // "-S", "-s",
        "-cpu", "cortex-a72",
        "-serial", "mon:stdio",
        "--no-reboot",
        "-nographic",
        "-kernel",
    });
    // zig fmt: on
    qemu.addArtifactArg(kernel);

    const run = b.step("run", "Run kernel in QEMU");
    run.dependOn(b.getInstallStep());
    run.dependOn(&qemu.step);
}
