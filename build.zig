const std = @import("std");

const Platform = enum {
    virt,
    raspi3b,
    raspi4b,
    raspi5b,
};

const QEMUMemoryUnit = enum {
    K,
    KiB,
    Kibibytes,
    M,
    MiB,
    Mibibytes,
    G,
    GiB,
    Gibibytes,

    pub fn asSuffix(self: QEMUMemoryUnit) []const u8 {
        return switch (self) {
            .K, .KiB, .Kibibytes => "K",
            .M, .MiB, .Mibibytes => "M",
            .G, .GiB, .Gibibytes => "G",
        };
    }
};

const QEMUOptions = struct {
    arch: std.Target.Cpu.Arch,
    machine: Platform,
    smp: usize,
    mem: struct { size: usize, unit: QEMUMemoryUnit },

    pub fn qemuExecutable(self: *const QEMUOptions) []const u8 {
        return switch (self.arch) {
            .aarch64 => "qemu-system-aarch64",
            else => @panic("unsupported cpu architecture"),
        };
    }

    pub fn machineArg(self: *const QEMUOptions) []const u8 {
        return @tagName(self.machine);
    }

    pub fn smpArg(self: *const QEMUOptions, b: *std.Build) []const u8 {
        return b.fmt("{d}", .{self.smp});
    }

    pub fn memArg(self: *const QEMUOptions, b: *std.Build) []const u8 {
        return b.fmt("{d}{s}", .{ self.mem.size, self.mem.unit.asSuffix() });
    }

    pub fn systemCommand(
        self: *const QEMUOptions,
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        kernel: *std.Build.Step.Compile,
    ) *std.Build.Step.Run {
        const run = b.addSystemCommand(&.{
            // zig fmt: off
            self.qemuExecutable(),
            "-machine", self.machineArg(),
            "-cpu", qemuCpuName(b, target),
            "-smp", self.smpArg(b),
            "-m", self.memArg(b),
            "-nographic", "-no-reboot",
            "-serial", "mon:stdio",
        });
        // zig fmt: on

        run.addArg("-kernel");
        run.addArtifactArg(kernel);

        run.stdio = .inherit;

        return run;
    }
};

const PlatformConfig = struct {
    target: std.Target.Query,
    qemu: ?QEMUOptions,
    linker_script: []const u8,
};

fn aarch64Target(cpu: *const std.Target.Cpu.Model) std.Target.Query {
    return .{
        .cpu_arch = .aarch64,
        .os_tag = .freestanding,
        .abi = .none,
        .ofmt = .elf,

        .cpu_model = .{ .explicit = cpu },

        .cpu_features_add = std.Target.aarch64.featureSet(&.{.strict_align}),
        .cpu_features_sub = std.Target.aarch64.featureSet(&.{ .fp_armv8, .neon }),
    };
}

fn qemuCpuName(b: *std.Build, target: std.Build.ResolvedTarget) []const u8 {
    const model = target.result.cpu.model;

    return switch (target.result.cpu.arch) {
        .aarch64 => switch (model) {
            &std.Target.aarch64.cpu.cortex_a53 => "cortex-a53",
            &std.Target.aarch64.cpu.cortex_a72 => "cortex-a72",
            &std.Target.aarch64.cpu.cortex_a76 => "cortex-a76",
            else => |cpu| @panic(b.fmt(
                "AArch64 CPU '{s}' is not supported",
                .{cpu.name},
            )),
        },
        else => @panic(b.fmt(
            "QEMU CPU mapping is not implemented for architecture '{s}'",
            .{@tagName(target.result.cpu.arch)},
        )),
    };
}

pub fn build(b: *std.Build) void {
    // platform build option
    const platform: Platform = b.option(Platform, "platform", "Target platform") orelse .virt;

    // platform decides target query and qemu options
    const platform_config: PlatformConfig = switch (platform) {
        .virt => .{
            .target = aarch64Target(
                &std.Target.aarch64.cpu.cortex_a53,
            ),
            .qemu = .{
                .arch = .aarch64,
                .machine = .virt,
                .smp = 1,
                .mem = .{
                    .size = 128,
                    .unit = .M,
                },
            },
            .linker_script = "src/linker/qemu-virt.ld",
        },

        .raspi3b => .{
            .target = aarch64Target(
                &std.Target.aarch64.cpu.cortex_a53,
            ),
            .qemu = .{
                .arch = .aarch64,
                .machine = .raspi3b,
                .smp = 4,
                .mem = .{
                    .size = 1,
                    .unit = .G,
                },
            },
            .linker_script = "src/linker/raspi3-aarch64.ld",
        },

        .raspi4b => .{
            .target = aarch64Target(
                &std.Target.aarch64.cpu.cortex_a72,
            ),
            .qemu = .{
                .arch = .aarch64,
                .machine = .raspi4b,
                .smp = 4,
                .mem = .{
                    .size = 2,
                    .unit = .G,
                },
            },
            .linker_script = "src/linker/raspi4-aarch64.ld",
        },

        .raspi5b => .{
            .target = aarch64Target(
                &std.Target.aarch64.cpu.cortex_a76,
            ),

            // No QEMU raspi5b machine currently.
            .qemu = null,

            .linker_script = "src/linker/raspi5-aarch64.ld",
        },
    };

    const target = b.resolveTargetQuery(platform_config.target);
    const optimize = b.standardOptimizeOption(.{
        // not a hard option but a suggestion, use `--release=safe` to force ReleaseSafe
        // or `--releaes=off` to force debug builds
        .preferred_optimize_mode = .ReleaseSafe,
    });

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
        .name = "dagos.bin",
        .root_module = kernel_mod,
        .use_lld = true,
    });

    kernel.setLinkerScript(b.path(platform_config.linker_script));

    // set output directory based on platform and architecture
    const output_dir = b.fmt("{s}/{s}/{s}/{s}", .{
        @tagName(platform),
        @tagName(target.result.cpu.arch),
        target.result.cpu.model.name,
        @tagName(optimize),
    });
    const install_kernel = b.addInstallArtifact(kernel, .{
        .dest_dir = .{
            .override = .{
                .custom = output_dir,
            },
        },
    });
    b.getInstallStep().dependOn(&install_kernel.step);

    if (platform_config.qemu != null) {
        const qemu = platform_config.qemu.?.systemCommand(b, target, kernel);
        const run_qemu = b.step("qemu", "Run kernel in QEMU");
        run_qemu.dependOn(b.getInstallStep());
        run_qemu.dependOn(&qemu.step);
    }
}
