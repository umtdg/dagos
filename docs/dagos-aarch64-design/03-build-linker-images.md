# 3. Build, Images, and Linker Scripts

## 3.1 Two output formats

Every successful kernel build should retain at least:

```text
zig-out/bin/kernel.elf
zig-out/bin/kernel.bin
zig-out/debug/kernel.map
zig-out/debug/kernel.disasm
```

`kernel.elf` is the authoritative debugging artifact. Keep DWARF and symbols available for GDB even if the loader consumes `kernel.bin`.

`kernel.bin` is a flat image generated from loadable sections. `NOLOAD` regions such as BSS and boot stacks occupy runtime physical memory but do not consume bytes in the flat image.

That distinction is why linker symbols must include both an **image end** and an **in-memory kernel reservation end**.

## 3.2 Common linker script plus platform fragment

Recommended structure:

```text
link/aarch64/kernel.ld
link/platform/<platform>.ld
```

Each platform fragment defines the boot-loader-dependent symbols and includes the common architectural layout.

### QEMU `virt`

For QEMU's raw AArch64 `-kernel` path, RAM begins at `0x40000000`, and QEMU's AArch64 raw kernel load offset is `0x80000`; this gives `0x40080000`. QEMU documents RAM base and DTB rules; the current loader source defines the `0x80000` AArch64 raw offset [QEMU-VIRT], [QEMU-ARM-BOOT].

```ld
/* link/platform/qemu_virt.ld */
KERNEL_PHYS_LOAD = 0x40080000;
KERNEL_LINK_LIMIT = 0x04000000; /* build-time guard, not discovered RAM size */

INCLUDE link/aarch64/kernel.ld
```

### QEMU `raspi3b` / `raspi4b`

QEMU's Raspberry Pi machine source uses `0x80000` as the Pi 3-family firmware/kernel location, and the common AArch64 raw loader uses a `0x80000` offset [QEMU-RASPI-SRC], [QEMU-ARM-BOOT]. For the flat raw-image development path, use:

```ld
/* link/platform/qemu_raspi3b.ld */
KERNEL_PHYS_LOAD = 0x00080000;
KERNEL_LINK_LIMIT = 0x04000000;
INCLUDE link/aarch64/kernel.ld
```

```ld
/* link/platform/qemu_raspi4b.ld */
KERNEL_PHYS_LOAD = 0x00080000;
KERNEL_LINK_LIMIT = 0x04000000;
INCLUDE link/aarch64/kernel.ld
```

Treat these as explicit QEMU boot contracts and verify the PC in GDB on every QEMU version upgrade. Do not infer real Raspberry Pi firmware addresses from these values.

### Real Raspberry Pi 3 / 4 / 5

Current Raspberry Pi documentation lists the legacy `kernel_address` default as `0x200000` for 64-bit kernels and explicitly notes that the legacy option remains useful for bare-metal development [RPI-LEGACY-BOOT]. Make the address explicit in both the linker and boot configuration:

```ld
/* link/platform/rpi3b.ld */
KERNEL_PHYS_LOAD = 0x00200000;
KERNEL_LINK_LIMIT = 0x04000000;
INCLUDE link/aarch64/kernel.ld
```

```ld
/* link/platform/rpi4b.ld */
KERNEL_PHYS_LOAD = 0x00200000;
KERNEL_LINK_LIMIT = 0x04000000;
INCLUDE link/aarch64/kernel.ld
```

```ld
/* link/platform/rpi5.ld */
KERNEL_PHYS_LOAD = 0x00200000;
KERNEL_LINK_LIMIT = 0x04000000;
INCLUDE link/aarch64/kernel.ld
```

Matching boot configuration:

```ini
arm_64bit=1
kernel=dagos.img
kernel_address=0x200000
```

Pi 5 ignores `arm_64bit` because current flagship models only support 64-bit kernels, but keeping architecture intent in generated configuration for Pi 3/4 is useful. On Pi 5 also use `os_check=0` for a deliberately non-Linux bare-metal image as documented by Raspberry Pi [RPI-CONFIG].

`KERNEL_LINK_LIMIT` above is only an assertion budget for accidental giant images. It is **not** the real RAM size. RAM size is discovered from the Device Tree.

## 3.3 Common AArch64 linker layout

A practical initial script:

```ld
/* link/aarch64/kernel.ld */
OUTPUT_ARCH(aarch64)
ENTRY(_start)

ASSERT(DEFINED(KERNEL_PHYS_LOAD), "platform must define KERNEL_PHYS_LOAD")

SECTIONS
{
    . = KERNEL_PHYS_LOAD;

    __kernel_phys_start = .;
    __kernel_image_start = .;

    .text.boot : ALIGN(16) {
        KEEP(*(.text.boot))
        KEEP(*(.text.boot.*))
    }

    .text.vectors : ALIGN(0x800) {
        __vectors_start = .;
        KEEP(*(.text.vectors))
        KEEP(*(.text.vectors.*))
        __vectors_end = .;
    }

    .text : ALIGN(16) {
        __text_start = .;
        *(.text .text.*)
        __text_end = .;
    }

    .rodata : ALIGN(16) {
        __rodata_start = .;
        *(.rodata .rodata.*)
        __rodata_end = .;
    }

    .data : ALIGN(16) {
        __data_start = .;
        *(.data .data.*)
        __data_end = .;
    }

    /* End of bytes that must exist in the flat image. */
    __kernel_image_end = .;

    .bss (NOLOAD) : ALIGN(16) {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(16);
        __bss_end = .;
    }

    /* Do not include this in the BSS clear range. */
    .boot_stack (NOLOAD) : ALIGN(16) {
        __boot_stack_bottom = .;
        KEEP(*(.boot_stack))
        KEEP(*(.boot_stack.*))
        . = ALIGN(16);
        __boot_stack_top = .;
    }

    /* Optional later: physical secondary trampoline or reserved bootstrap tables. */
    .bootstrap (NOLOAD) : ALIGN(4096) {
        __bootstrap_start = .;
        KEEP(*(.bootstrap))
        KEEP(*(.bootstrap.*))
        __bootstrap_end = .;
    }

    . = ALIGN(4096);
    __kernel_phys_end = .;

    /DISCARD/ : {
        *(.comment)
        *(.note .note.*)
    }
}

ASSERT((__vectors_start & 0x7ff) == 0,
       "VBAR_EL1 table must be 2048-byte aligned")
ASSERT((__boot_stack_top & 0xf) == 0,
       "boot stack top must be 16-byte aligned")
ASSERT(__bss_end <= __boot_stack_bottom,
       "BSS must not overlap active boot stack")
ASSERT((__kernel_phys_end - __kernel_phys_start) <= KERNEL_LINK_LIMIT,
       "kernel reservation exceeds platform link budget")
```

The exact `INCLUDE` search path is a build-system concern. If LLD path handling becomes inconvenient, have `build.zig` generate a final linker script by concatenating/templating the platform constants and common script. Preserve the same conceptual split.

## 3.4 Why `__kernel_image_end` and `__kernel_phys_end` differ

Suppose:

```text
.text + .rodata + .data end at 0x00228000
.bss ends at                0x00234000
boot stack ends at          0x00238000
page alignment gives        0x00239000
```

The flat `kernel.bin` may stop near `0x00228000`, but physical memory from `0x00200000` through `0x00239000` is occupied by the kernel at runtime.

The physical allocator must reserve:

```text
[__kernel_phys_start, __kernel_phys_end)
```

not merely the bytes present in the flat image.

## 3.5 Do not clear the boot stack

An unsafe layout is:

```text
.bss:
    globals
    boot stack
```

followed by:

```text
set SP into boot stack
clear all .bss
```

The clear loop can overwrite return addresses, spilled registers, or local variables on the active stack. Keep the boot stack outside `[__bss_start, __bss_end)`.

## 3.6 Vector-table section constraints

`VBAR_EL1` points to a 2048-byte vector table containing 16 fixed 128-byte slots [ARM-EXC]. Require:

```text
__vectors_start % 2048 == 0
__vectors_end - __vectors_start == 2048
```

Add the second assertion once `vectors.S` is final:

```ld
ASSERT((__vectors_end - __vectors_start) == 0x800,
       "EL1 vector table must occupy exactly 2048 bytes")
```

## 3.7 Future high-half linking

Do not complicate the first hello-world image with separate virtual/load addresses. Begin identity-linked and identity-mapped.

After bootstrap MMU support works, add an explicit virtual kernel base. Two reasonable designs exist:

### Design A: linked high, loaded low using `AT(...)`

```ld
. = KERNEL_VIRT_BASE;
.text : AT(KERNEL_PHYS_LOAD) { ... }
```

This makes normal symbols high virtual addresses after the transition. Linker load-memory-address arithmetic must remain carefully synchronized.

### Design B: initially link physical, then later migrate the linker policy

This is simpler during early development and is the recommended progression here.

When changing to high-half linking, preserve physical linker symbols for:

- secondary CPU entry
- firmware CPU-start APIs
- initial page-table descriptors
- physical kernel reservation

Do not try to recover those with arbitrary subtraction scattered through the kernel; centralize conversions in the memory-layout layer.

## 3.8 Linker script is architecture + platform, not one or the other

Architecture-dependent linker information:

- AArch64 output architecture
- section alignment
- vector-table alignment
- AArch64 boot code location/order
- later virtual-address arrangement

Platform-dependent linker information:

- physical load address
- any loader-imposed maximum or special region
- boot trampoline placement when a particular firmware requires one

Therefore the base-plus-fragment structure is the correct model. Do not create a generic `32-bit.ld` and `64-bit.ld` under `platform/`; a future AArch32 port needs its own architecture linker layout because its ABI, vectors, MMU, and boot code are different.

## 3.9 Raspberry Pi generated boot directory

For real boards, generate a reproducible boot directory rather than maintaining an SD card manually:

```text
zig-out/boot/rpi4b/
    dagos.img
    config.txt
    bcm2711-rpi-4-b.dtb       # supplied from chosen firmware bundle
    overlays/...              # only if needed
    firmware files required by that board/boot path
```

For Pi 3/4, an initial console-oriented `config.txt` may contain:

```ini
arm_64bit=1
kernel=dagos.img
kernel_address=0x200000
enable_uart=1
dtoverlay=disable-bt
```

For bare metal, Linux's `hciuart` service does not exist, so only the firmware/Device-Tree effect of the overlay matters.

For Pi 5:

```ini
kernel=dagos.img
kernel_address=0x200000
os_check=0
```

The primary Pi 5 debug UART is UART10 on the dedicated debug connector [RPI-UART]. Avoid making RP1 PCIe initialization a prerequisite for first output.
