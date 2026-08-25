# 12. References

The design uses official architecture/platform documentation as the primary source. Linux and Raspberry Pi kernel DTS files are used as integration references where they expose board wiring and firmware conventions.

## [ARM-EXC] Arm — Exception model

Arm, *Learn the Architecture: Exception model*.

https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/Learn%20the%20Architecture/Exception%20model.pdf

Use for:

- exception levels
- `VBAR_ELx`
- 16-entry vector table and offsets
- exception return concepts
- syndrome/return registers

## [ARM-EL-TRANSITION] Arm — Changing exception level and security state

https://developer.arm.com/community/arm-community-blogs/b/tools-software-ides-blog/posts/changing-exception-level-and-security-state-with-an-armv8a-fixed-virtual-platform

Use as an explanatory example for:

- EL2 → EL1 transition
- `HCR_EL2`
- `SPSR_EL2`
- `ELR_EL2`
- `ERET`
- timer/FP trap setup concepts

The Arm Architecture Reference Manual remains normative for exact register fields.

## [ARM-MM] Arm — Memory management

Arm, *Learn the Architecture: Memory management*.

https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/Learn%20the%20Architecture/LearnTheArchitecture-MemoryManagement-101811_0100_00_en.pdf

Use for:

- translation granules
- page-table levels
- VA indexing
- descriptors
- TCR/TTBR/MAIR concepts
- memory attributes and translation

## [AAPCS64] Arm ABI — AAPCS64

https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst

Use for:

- AArch64 function calling convention
- callee-saved registers
- stack model
- 16-byte stack alignment
- Zig ↔ assembly ABI boundaries

## [ARM64-BOOT] Linux kernel documentation — Booting AArch64 Linux

https://cdn.kernel.org/doc/html/latest/arch/arm64/booting.html

This is a Linux boot protocol, not the Arm architecture itself, but QEMU and firmware commonly use conventions based on it. Use for:

- AArch64 kernel entry state
- DTB handoff conventions
- secondary CPU startup
- PSCI
- spin-table
- secondary register state

Always distinguish protocol requirements from architectural requirements.

## [QEMU-VIRT] QEMU — `virt` generic virtual platform

https://www.qemu.org/docs/master/system/arm/virt.html

Use for:

- 64-bit CPU selection requirement
- QEMU `virt` RAM base
- DTB location/handoff rules
- PL011 presence
- GIC version configuration
- warning that most device addresses should be discovered from DTB

## [QEMU-RASPI] QEMU — Raspberry Pi boards

https://www.qemu.org/docs/master/system/arm/raspi.html

Use for:

- implemented Pi board models
- CPU models/core counts
- PL011/AUX emulation
- missing-device limitations

## [QEMU-ARM-BOOT] QEMU source — AArch64 Arm kernel loader

Current QEMU loader implementation/source reference:

https://github.com/qemu/qemu/blob/master/hw/arm/boot.c

Use to verify the current raw AArch64 kernel-load offset and loader behavior. Treat source implementation details as version-sensitive; verify again when changing QEMU versions.

## [QEMU-RASPI-SRC] QEMU source — Raspberry Pi machine

https://github.com/qemu/qemu/blob/master/hw/arm/raspi.c

Use to verify QEMU Raspberry Pi boot shim/load constants and model implementation details. These are emulator contracts, not Raspberry Pi firmware contracts.

## [DT-FLAT] Devicetree Specification — Flattened DTB format

https://devicetree-specification.readthedocs.io/en/stable/flattened-format.html

If the stable URL layout changes, use the current flattened-format chapter from:

https://devicetree-specification.readthedocs.io/

Use for:

- DTB header
- memory reservation block
- structure and strings blocks
- big-endian encoding
- alignment
- versioning

## [DT-SPEC] Devicetree Specification — device tree basics and required nodes

https://devicetree-specification.readthedocs.io/en/stable/devicetree-basics.html

https://devicetree-specification.readthedocs.io/en/latest/chapter3-devicenodes.html

Use for:

- `reg`
- `ranges`
- `#address-cells`
- `#size-cells`
- `/memory`
- `/reserved-memory`
- `/chosen`
- `/cpus`

## [RPI-CONFIG] Raspberry Pi — `config.txt`

https://www.raspberrypi.com/documentation/computers/config_txt.html

Use for current firmware controls including:

- `kernel=`
- `arm_64bit`
- `armstub`
- Pi 5 `os_check`
- Pi 5-specific boot controls

Current documentation states Pi 5-family flagship models only support a 64-bit kernel.

## [RPI-LEGACY-BOOT] Raspberry Pi — legacy `config.txt` options

https://www.raspberrypi.com/documentation/computers/legacy_config_txt.html

Use for bare-metal-relevant legacy controls such as `kernel_address`. Current documentation states defaults of `0x8000` for 32-bit and `0x200000` for 64-bit legacy kernel loading and explicitly notes these options may still benefit bare-metal development.

## [RPI-UART] Raspberry Pi — UART configuration

https://www.raspberrypi.com/documentation/computers/configuration.html

Also:

https://www.raspberrypi.com/documentation/configuration/computers/raspberry-pi.html

Use for:

- PL011 versus mini UART
- Pi 3/4 UART routing
- Pi 5 UART10 debug console
- 3.3-V electrical warning
- `disable-bt` and other UART overlays

## [RPI-DT] Raspberry Pi firmware / Device Tree overlay documentation

https://github.com/raspberrypi/firmware/blob/master/boot/overlays/README

Use for the firmware's Device Tree loading/overlay model.

## [RPI-BCM2711-DTS] Raspberry Pi Linux — BCM2711 DTS

https://github.com/raspberrypi/linux/blob/rpi-6.18.y/arch/arm/boot/dts/broadcom/bcm2711.dtsi

Use as an integration reference for:

- BCM2711 bus `ranges`
- GIC-400/GICv2 layout
- Cortex-A72 CPU nodes
- spin-table `cpu-release-addr`

Do not treat Linux driver implementation choices as architectural requirements.

## [RPI-BCM2712-DTS] Raspberry Pi Linux — BCM2712 DTS

https://github.com/raspberrypi/linux/blob/rpi-6.18.y/arch/arm64/boot/dts/broadcom/bcm2712.dtsi

Use as an integration reference for:

- BCM2712 bus topology
- UART10 `arm,pl011` node
- GIC-400/GICv2 description

## [RPI-BCM2712-RPI-DTS] Raspberry Pi Linux — BCM2712 Raspberry Pi integration

https://github.com/raspberrypi/linux/blob/rpi-6.18.y/arch/arm64/boot/dts/broadcom/bcm2712-rpi.dtsi

Board-specific files under the same directory enable/configure devices such as the Pi 5 debug UART.

## [RPI-BCM2836-DTS] Raspberry Pi Linux — BCM2836 family DTS / local IRQ reference

https://github.com/raspberrypi/linux/blob/rpi-6.18.y/arch/arm/boot/dts/broadcom/bcm2836.dtsi

Related local interrupt-controller definitions:

https://github.com/raspberrypi/linux/blob/rpi-6.18.y/include/linux/irqchip/irq-bcm2836.h

Use as an integration reference for Pi 3-family local timer/mailbox interrupt routing.

## Normative source not directly linked here

For exact system-register bit definitions, exception syndrome encodings, TLBI/barrier rules, and feature-register semantics, use the Arm Architecture Reference Manual for the minimum Armv8-A/AArch64 architecture version you decide to support. The smaller Arm “Learn the Architecture” guides are explanatory; the architecture manual is normative.

## [RPI-ARMSTUB8] Raspberry Pi — public AArch64 Arm stub

https://github.com/raspberrypi/tools/blob/master/armstubs/armstub8.S

Use as an implementation reference for the Raspberry Pi firmware-to-kernel handoff:

- EL3 setup followed by transition to EL2
- secondary-core parking/release slots
- primary DTB pointer in `x0`
- `x1-x3` cleared before kernel branch

The repository is an implementation reference; pin the firmware/stub revision used by the actual test image because firmware behavior is version-sensitive.

## [ARM-REGS] Arm — Architecture system-register reference

Arm's published Architecture Registers material for Armv8-A/A-profile:

https://documentation-service.arm.com/static/60df1943677cf7536a55ddef

Use the current Arm Architecture Reference Manual / register XML or HTML for the architecture revision being targeted when encoding system-register fields. In particular verify:

- `HCR_EL2`
- `CNTHCTL_EL2`
- `SCTLR_EL1`
- `TCR_EL1`
- `MAIR_EL1`
- `ID_AA64MMFR0_EL1`
- `CPACR_EL1` / `CPTR_EL2`
- `ESR_EL1` exception classes and ISS fields

For the non-VHE (`HCR_EL2.E2H=0`) Armv8 baseline, `CNTHCTL_EL2.EL1PCTEN` is bit 0 and `EL1PCEN` is bit 1. Recheck field layouts when adding extensions rather than assuming all feature-dependent register views are identical.

## [LINUX-ARM64-HEAD] Linux arm64 early entry implementation

https://github.com/torvalds/linux/blob/master/arch/arm64/kernel/head.S

Related system-register constants:

https://github.com/torvalds/linux/blob/master/arch/arm64/include/asm/sysreg.h

Use as a mature implementation reference for:

- preserving boot arguments
- EL1/EL2 normalization
- sane MMU-off `SCTLR_EL1` state
- secondary holding-pen/entry patterns
- MMU-enable sequencing

Do not copy Linux feature policy wholesale. Dagos intentionally supports a narrower initial feature set, but Linux is useful for identifying architectural state that a small tutorial often forgets to initialize.
