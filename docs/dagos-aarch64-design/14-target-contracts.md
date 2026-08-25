# 14. Per-Target Boot and Bring-Up Contracts

This chapter is the checklist that turns the generic AArch64 design into six reproducible targets. A target contract describes only what Dagos is allowed to assume **before** Device Tree parsing and normal platform initialization. Everything else must be discovered or validated.

Source labels such as `[QEMU-VIRT]` and `[RPI-ARMSTUB8]` are defined in [12. References](12-references.md).

## 14.1 Common AArch64 kernel-entry contract

Dagos' shared AArch64 entry wrapper is designed for the following input shape:

```text
execution state     AArch64
MMU                 off
kernel image        already loaded at the link/load PA selected by the target
x0                  DTB physical address, if this target's configured loader promises it
x1-x3               reserved; preserved until the target contract has been validated
DAIF                immediately masked by Dagos, regardless of incoming state
CurrentEL           EL1 or EL2 accepted
SP                  ignored; Dagos establishes its own stack before calling Zig
VBAR_EL1            ignored; Dagos installs its own table
secondary CPUs      must not execute global initialization
```

The common code must **verify** rather than silently depend on the entries that can be checked cheaply:

- `CurrentEL` is EL1 or EL2;
- `x0` is suitably aligned before interpreting it as an FDT pointer;
- the prospective DTB begins with big-endian `0xd00dfeed` before using its size/offsets;
- the linked kernel start corresponds to the target's expected execution address;
- the first stack is 16-byte aligned;
- the runtime platform compatibility strings later match the selected target.

A target for which `x0` is not a DTB pointer must provide a different tiny platform wrapper and translate its boot convention into Dagos' common `BootInfo` representation.

## 14.2 QEMU `virt`

### Build contract

```text
platform             qemu_virt
architecture         aarch64
link PA              0x4008_0000 for the raw `-kernel` path described below
image                 kernel.bin supplied with `-kernel`
early serial          PL011
initial GIC policy    GICv2
hardware discovery    generated DTB
```

QEMU documents `virt` RAM as beginning at `0x40000000`. The current Arm raw AArch64 kernel loader uses a `0x80000` kernel offset, yielding `0x40080000`; the implementation detail must be rechecked when upgrading QEMU `[QEMU-VIRT] [QEMU-ARM-BOOT]`.

Do not treat the rest of the `virt` memory map as a stable kernel ABI. QEMU explicitly directs guests to the generated DTB for device locations `[QEMU-VIRT]`.

### Recommended first run shape

```text
qemu-system-aarch64 \
    -machine virt,gic-version=2 \
    -cpu cortex-a72 \
    -smp 4 \
    -m 1G \
    -kernel zig-out/bin/kernel.bin \
    -display none \
    -serial mon:stdio
```

The exact CPU model is development policy, not a kernel ABI. Always specify a 64-bit CPU because QEMU `virt`'s default CPU selection is not an AArch64 development contract `[QEMU-VIRT]`.

### Entry checks

At the first architecture breadcrumb record:

```text
PC             == linked/raw load address
CurrentEL      == EL1 or EL2 according to selected QEMU configuration
x0             points to valid DTB
DT /memory     begins at 0x40000000
DT CPU count   equals requested -smp count
DT GIC         matches forced gic-version=2
DT UART        is compatible with arm,pl011
```

Do not hardcode `-smp 4` into the kernel. Run later tests with `-smp 1`, `-smp 2`, and `-smp 4`.

### EL2 test mode

Keep a dedicated QEMU invocation whose configuration causes the kernel to be entered with EL2 available/active so that the EL2 -> EL1h path is tested, not merely compiled. Record the observed `CurrentEL` in the test log. The exact QEMU command-line mechanism can change with machine/CPU configuration, so make the acceptance criterion the observed architectural state rather than a guessed flag.

## 14.3 QEMU `raspi3b`

### Build contract

```text
platform             qemu_raspi3b
architecture         aarch64
CPU model            Cortex-A53, 4 cores in the model
link PA              0x0008_0000 for the selected QEMU raw-image path
early serial          PL011
interrupt family      BCM283x/BCM2836-style, not generic QEMU virt GIC
hardware discovery    DTB + selected-model knowledge
```

QEMU documents the board model and its emulated PL011/AUX devices `[QEMU-RASPI]`. QEMU's Raspberry Pi machine source is the authoritative emulator-side source for the boot shim and release-slot behavior `[QEMU-RASPI-SRC]`.

### Secondary CPUs

For the AArch64 Raspberry Pi machine path, QEMU's boot shim uses spin/release locations corresponding to the Raspberry Pi-style addresses around:

```text
CPU0  0xd8
CPU1  0xe0
CPU2  0xe8
CPU3  0xf0
```

The secondary path waits with `WFE` until released, then branches to the supplied entry `[QEMU-RASPI-SRC]`.

Treat these values as the **QEMU machine contract**, not as generic AArch64 constants. Once FDT CPU nodes provide an `enable-method` and `cpu-release-addr`, the SMP layer consumes that description rather than reaching into platform constants.

### Bring-up checks

Verify:

```text
CurrentEL
DTB magic and total size
CPU compatible / count
CPU enable-method
PL011 address after bus translation
RAM region
interrupt-controller nodes
```

Do not assume the real Pi 3 and QEMU Pi 3 expose every peripheral identically merely because they share SoC ancestry.

## 14.4 QEMU `raspi4b`

### Build contract

```text
platform             qemu_raspi4b
architecture         aarch64
CPU model            Cortex-A72, 4 cores in the model
link PA              0x0008_0000 for the selected QEMU raw-image path
early serial          PL011
interrupt family      BCM2711/GICv2 path
hardware discovery    DTB + selected-model knowledge
```

QEMU documents the model and explicitly lists hardware that is not implemented, including important Pi 4 devices that are irrelevant to early kernel bring-up `[QEMU-RASPI]`.

Use the same design rule as `qemu_raspi3b`: emulator source can establish the pre-DTB boot contract, but driver/device configuration after the parser exists should come from FDT wherever practical.

### Bring-up checks

In addition to the generic checks:

```text
CPU compatible     Cortex-A72 family description
GIC compatible     GICv2/GIC-400-style description expected for BCM2711 model
PL011 discovered   matches early-console fallback
CPU startup data   valid before trying secondary bring-up
```

Do not gate hello-world success on QEMU implementing PCIe, Ethernet, USB, or other unrelated Pi 4 devices.

## 14.5 Physical Raspberry Pi 3

### Reproducible boot directory

Generate the boot partition content from the build. Do not depend on a manually edited SD card whose firmware/config version is unknown.

Initial intended `config.txt` policy:

```ini
arm_64bit=1
kernel=dagos.img
kernel_address=0x200000
enable_uart=1
dtoverlay=disable-bt
```

`kernel_address=0x200000` is deliberately explicit and must match the linker fragment; current Raspberry Pi documentation lists `0x200000` as the legacy 64-bit default and notes the option's relevance to bare-metal use `[RPI-LEGACY-BOOT]`.

`disable-bt` is used here to make PL011 routing deterministic for the early console. The exact overlay/config behavior is platform firmware policy and must be pinned with the firmware bundle `[RPI-UART] [RPI-DT]`.

### Firmware handoff

The public Raspberry Pi AArch64 arm stub is an implementation reference showing this pattern `[RPI-ARMSTUB8]`:

```text
firmware/arm stub starts with higher privilege
        |
        +-- performs low-level setup
        +-- transitions to EL2
        +-- parks non-primary cores in WFE/release loops
        +-- primary x0 = DTB pointer
        +-- primary x1-x3 = 0
        v
Dagos kernel
```

Pin and record the actual firmware/stub version placed on the card. Do not assume every future firmware revision is identical to the current public source.

### Early console fallback

The documented CPU-visible PL011 address used for early-console work on Pi 3 is:

```text
0x3f201000
```

`[RPI-UART]`.

This fallback exists only to make the first bytes possible before FDT parsing. Once FDT is available, resolve the selected UART and its parent-bus `ranges` and verify that discovery agrees with the fallback.

### Hardware test log

For every firmware update, capture at least:

```text
firmware bundle/revision
config.txt
kernel image hash
entry PC
entry CurrentEL
entry MPIDR_EL1
x0 value
DTB magic/size/model/compatible
UART fallback PA and discovered PA
```

## 14.6 Physical Raspberry Pi 4

Initial generated configuration can use the same explicit 64-bit/load-address policy:

```ini
arm_64bit=1
kernel=dagos.img
kernel_address=0x200000
enable_uart=1
dtoverlay=disable-bt
```

The early PL011 fallback is:

```text
0xfe201000
```

`[RPI-UART]`.

The BCM2711 integration reference describes Cortex-A72 CPU nodes, GIC-400/GICv2, bus `ranges`, and spin-table `cpu-release-addr` properties `[RPI-BCM2711-DTS]`.

Do not hardcode the DTS' release addresses into `arch/aarch64`. The FDT CPU topology parser should populate `CpuInfo` and the generic spin-table backend should consume it.

The real-board bring-up progression is:

```text
polling PL011
   -> validate DTB/model
   -> translate PL011 through ranges and compare
   -> discover RAM/reservations
   -> MMU
   -> GICv2
   -> generic timer
   -> spin-table secondary startup
```

## 14.7 Physical Raspberry Pi 5

Pi 5 deserves a separate contract. Do not assume every Pi 3/4 firmware implementation detail carries forward merely because the kernel API should look similar.

### Generated configuration

Initial policy:

```ini
kernel=dagos.img
kernel_address=0x200000
os_check=0
enable_uart=1
```

Pi 5 is a 64-bit-kernel platform; `os_check=0` is documented for bare-metal development `[RPI-CONFIG]`.

Pin the firmware/EEPROM-facing boot environment used for each test. If a firmware revision changes the load or DT handoff behavior, treat that as a target-contract change and update this document plus the build artifact.

### Early serial

Use the dedicated Pi 5 debug UART rather than making RP1/PCIe initialization a prerequisite for console output.

The early CPU-visible address documented for this PL011 is:

```text
0x107d001000
```

`[RPI-UART]`.

The BCM2712 DTS describes the corresponding UART node as `arm,pl011`; its bus-relative address is translated through parent ranges `[RPI-BCM2712-DTS]`.

### Entry state policy

The common Dagos wrapper accepts EL1 or EL2, so Pi 5 does not need a guessed fixed initial EL in source code. On the first real-board test of every pinned boot environment, record:

```text
CurrentEL
MPIDR_EL1
x0
DTB magic/model/compatible
SCTLR_EL1.M
```

If `x0` is not a valid DTB under the selected boot configuration, add a Pi5-specific tiny wrapper/firmware adapter rather than weakening the common architecture contract with heuristics.

### What is deliberately postponed

Do not initialize RP1, PCIe, general-purpose RP1 UARTs, USB, Ethernet, or storage as part of the first Pi 5 kernel milestone. The dedicated debug PL011 is the bootstrap console. RP1 support is a later SoC/PCIe project.

## 14.8 Target-specific assembly selection

Initial build selection should be:

```text
qemu_virt      -> platform/common/asm/aarch64_dtb_boot.S
qemu_raspi3b   -> platform/common/asm/aarch64_dtb_boot.S
qemu_raspi4b   -> platform/common/asm/aarch64_dtb_boot.S
rpi3b          -> platform/common/asm/aarch64_dtb_boot.S
rpi4b          -> platform/common/asm/aarch64_dtb_boot.S
rpi5           -> platform/common/asm/aarch64_dtb_boot.S, only after x0/EL contract is verified
```

The build system must still model these as six platform choices. Sharing one object is code reuse; it does not merge their contracts.

A platform gets its own `platform/<name>/asm/boot.S` only if it must adapt something **before a reliable AArch64 stack exists**, for example:

- DTB is supplied in a different register;
- a firmware metadata structure must be decoded before the common entry;
- unexpected CPUs enter `_start` and must be parked before touching global state;
- the load address requires a tiny relocation/trampoline stage;
- the kernel receives control in an execution state outside the common EL1/EL2 contract.

Do not create platform assembly merely to program UART/GPIO/GIC. Once the common stack exists, those belong in Zig drivers/platform code.

## 14.9 Contract verification before enabling higher subsystems

Every platform should pass the following sequence independently:

```text
A. GDB/serial-visible _start
B. private/aligned stack established
C. EL1h reached
D. BSS clear verified
E. VBAR_EL1 installed
F. early PL011 prints
G. deliberate BRK reaches current-EL sync handler
H. DTB validates
I. /compatible matches selected platform
J. discovered UART agrees with bootstrap UART
K. discovered memory map contains kernel and excludes reservations correctly
L. only then begin MMU work
```

Do not debug MMU, GIC, SMP, and an unverified loader contract simultaneously.

## 14.10 Platform contract table

| Target | Link/load PA in this design | Early UART | Initial interrupt path | Secondary-start direction | Runtime source of truth |
|---|---:|---|---|---|---|
| QEMU `virt` | `0x40080000` | PL011; DT authoritative | force GICv2 initially | PSCI/DT-described | generated DTB |
| QEMU `raspi3b` | `0x00080000` | PL011 | BCM283x/BCM2836 style | QEMU Pi spin/release model, then DT abstraction | DTB + QEMU model contract |
| QEMU `raspi4b` | `0x00080000` | PL011 | GICv2/BCM2711 | QEMU Pi spin/release model, then DT abstraction | DTB + QEMU model contract |
| Pi 3 | explicit `0x00200000` | PL011 `0x3f201000` bootstrap fallback | BCM local + legacy controller | firmware/DT-described | firmware DTB |
| Pi 4 | explicit `0x00200000` | PL011 `0xfe201000` bootstrap fallback | GICv2 | spin-table/DT-described | firmware DTB |
| Pi 5 | explicit `0x00200000` | UART10 PL011 `0x107d001000` fallback | GICv2 | firmware/DT-described; verify concrete handoff | firmware DTB |

The table contains the **chosen development contracts**, not immutable architectural truths. Values derived from emulator or firmware behavior are version-pinned build assumptions and must remain testable.
