# 2. Project and Assembly Structure

## 2.1 Proposed source tree

```text
.
├── build.zig
├── build.zig.zon
├── link/
│   ├── aarch64/
│   │   └── kernel.ld
│   └── platform/
│       ├── qemu_virt.ld
│       ├── qemu_raspi3b.ld
│       ├── qemu_raspi4b.ld
│       ├── rpi3b.ld
│       ├── rpi4b.ld
│       └── rpi5.ld
│
├── src/
│   ├── main.zig
│   │
│   ├── arch/
│   │   ├── arch.zig
│   │   └── aarch64/
│   │       ├── arch.zig
│   │       ├── boot.zig
│   │       ├── cpu.zig
│   │       ├── registers.zig
│   │       ├── barriers.zig
│   │       ├── atomics.zig
│   │       ├── exceptions.zig
│   │       ├── context.zig
│   │       ├── timer.zig
│   │       ├── mmu.zig
│   │       ├── pagetable.zig
│   │       ├── tlb.zig
│   │       ├── cache.zig
│   │       ├── user.zig
│   │       ├── abi/
│   │       │   ├── exception_frame_layout.zig
│   │       │   └── exception_frame.zig
│   │       └── asm/
│   │           ├── include/
│   │           │   ├── common.inc
│   │           │   ├── sysreg.inc
│   │           │   └── exception_frame.inc   # generated
│   │           ├── entry.S
│   │           ├── el.S
│   │           ├── vectors.S
│   │           ├── context.S
│   │           ├── user.S
│   │           └── secondary.S
│   │
│   ├── firmware/
│   │   ├── fdt/
│   │   │   ├── fdt.zig
│   │   │   ├── header.zig
│   │   │   ├── iterator.zig
│   │   │   ├── cells.zig
│   │   │   └── translate.zig
│   │   └── psci.zig
│   │
│   ├── drivers/
│   │   ├── mmio.zig
│   │   ├── serial/
│   │   │   ├── serial.zig
│   │   │   ├── pl011.zig
│   │   │   └── bcm_aux_uart.zig
│   │   ├── irq/
│   │   │   ├── controller.zig
│   │   │   ├── gicv2.zig
│   │   │   ├── bcm2836_local.zig
│   │   │   └── bcm283x_armctrl.zig
│   │   └── gpio/
│   │       └── ...
│   │
│   ├── soc/
│   │   ├── bcm2837/
│   │   │   └── soc.zig
│   │   ├── bcm2711/
│   │   │   └── soc.zig
│   │   └── bcm2712/
│   │       └── soc.zig
│   │
│   ├── platform/
│   │   ├── platform.zig
│   │   ├── common/
│   │   │   ├── raspberry_pi.zig
│   │   │   └── asm/
│   │   │       └── aarch64_dtb_boot.S
│   │   ├── qemu_virt/
│   │   │   └── platform.zig
│   │   ├── qemu_raspi3b/
│   │   │   └── platform.zig
│   │   ├── qemu_raspi4b/
│   │   │   └── platform.zig
│   │   ├── rpi3b/
│   │   │   └── platform.zig
│   │   ├── rpi4b/
│   │   │   └── platform.zig
│   │   └── rpi5/
│   │       └── platform.zig
│   │
│   └── kernel/
│       ├── boot.zig
│       ├── console.zig
│       ├── panic.zig
│       ├── percpu.zig
│       ├── smp.zig
│       ├── irq.zig
│       ├── syscall.zig
│       ├── task.zig
│       ├── scheduler.zig
│       ├── process.zig
│       └── mm/
│           ├── range.zig
│           ├── early.zig
│           ├── physical.zig
│           ├── virtual.zig
│           ├── address_space.zig
│           ├── layout.zig
│           └── heap.zig
│
└── tools/
    └── gen_asm_offsets.zig
```

This is a boundary map, not a requirement to create every empty file immediately.

## 2.2 Why platform `boot.S` files exist

The ELF entry symbol is where the platform boot protocol meets the architecture. Keep the platform entry file deliberately tiny so differences remain explicit without duplicating architecture logic.

Each selected platform links exactly one `_start` implementation. The current six targets can share one wrapper after the boot contract has been verified:

```asm
/* platform/common/asm/aarch64_dtb_boot.S */
#include "common.inc"

.section .text.boot, "ax"
.global _start
.type _start, %function
_start:
    /* x0-x3 remain untouched: the architecture entry preserves them. */
    b aarch64_boot_entry
```

QEMU's AArch64 Linux-style raw `-kernel` path supplies the DTB in `x0`. Raspberry Pi's public 64-bit Arm stub likewise loads the primary DTB pointer into `x0`, zeros `x1-x3`, parks the secondary cores, and branches to the kernel from EL2. A platform with a different contract can replace this one source with `platform/<name>/asm/boot.S` without duplicating `arch/aarch64/asm/entry.S`.

The common AArch64 entry lives in:

```text
src/arch/aarch64/asm/entry.S
```

Benefits:

1. `_start` remains allowed to differ when a future platform has a genuinely different entry contract.
2. EL normalization, DAIF handling, register preservation, and the transition to Zig are not copied six times.
3. Platform code cannot accidentally grow into an alternate implementation of AArch64 exception setup.
4. QEMU `virt`, QEMU Pi, and real Pi can initially use nearly identical one-branch wrappers while still documenting different load addresses and loader behavior.

If two platforms later prove to have exactly the same boot contract, their build descriptions may select the same wrapper object. Do not remove the conceptual boundary merely to save one branch instruction in source.

## 2.3 Common assembly include directory

Build every AArch64 `.S` file with an include path for:

```text
src/arch/aarch64/asm/include
```

Use includes for constants and macros, not for large executable routines.

### `common.inc`

Appropriate contents:

- function-symbol declaration macros
- alignment macros
- local-label conventions
- `DAIF` mask/unmask helpers
- small `adrp`/`add` address-load macro if it improves readability
- compile-time assembly constants that are genuinely architectural

Do not hide entire boot algorithms inside a macro. Debugging macro-expanded assembly becomes harder than debugging normal labels/functions.

### `sysreg.inc`

Use only if named bit definitions substantially improve readability. Prefer:

```asm
orr x0, x0, #HCR_RW
```

over unexplained hexadecimal register values.

Keep the source of each bit definition documented beside it with the Arm register name and field.

### `exception_frame.inc`

This file should be generated from a single target-independent Zig layout description. It provides assembly constants such as:

```asm
.equ EXC_X0,       0
.equ EXC_X1,       8
...
.equ EXC_X30,      240
.equ EXC_SP_EL0,   248
.equ EXC_ELR,      256
.equ EXC_SPSR,     264
.equ EXC_ESR,      272
.equ EXC_FAR,      280
.equ EXC_VECTOR,   288
.equ EXC_RESERVED, 296
.equ EXC_FRAME_SIZE, 304
```

The exact values are part of the ABI between `vectors.S` and `exceptions.zig`.

## 2.4 Single source of truth for assembly/Zig layouts

Manual duplication of exception offsets is a recurring kernel bug source. Use this flow:

```text
exception_frame_layout.zig
        |
        +----> exception_frame.zig compile-time assertions
        |
        +----> tools/gen_asm_offsets.zig
                    |
                    v
          generated/exception_frame.inc
                    |
                    v
                 vectors.S
```

`exception_frame_layout.zig` should contain only target-independent integer constants/enums, so the host build can import it safely.

`exception_frame.zig` defines the actual `extern struct` and asserts:

```text
@offsetOf(ExceptionFrame, "x") ...
@sizeOf(ExceptionFrame) == layout.frame_size
@alignOf(ExceptionFrame) compatible with 16-byte SP invariant
```

Do the same later for context-switch frames if assembly and Zig both inspect their memory layout.

## 2.5 Assembly file responsibilities

### `entry.S`

Owns the architecture-common primary entry after the platform wrapper:

- preserve boot arguments
- read `CurrentEL`
- mask DAIF
- establish or select the primary boot stack
- branch to EL normalization
- clear/initialize architecture state needed before Zig
- eventually call the Zig early entry with a defined ABI

It must not initialize PL011 or parse a DTB.

### `el.S`

Owns exception-level transitions:

- EL2 → EL1h
- direct EL1h normalization
- explicit unsupported-EL trap labels

This separation makes the system-register setup inspectable without mixing it with BSS clearing and stack code.

### `vectors.S`

Owns:

- 2048-byte aligned EL1 vector table
- 16 128-byte vector slots
- common exception prologue
- exception-frame save
- call to Zig exception dispatcher
- exception-frame restore
- `ERET`

### `context.S`

Owns scheduler context switches, not architectural exception entry. The context frame is smaller because AAPCS64 call-preserved state is sufficient at a scheduler boundary.

### `user.S`

Owns the final architecture-sensitive transition from an already prepared EL1 context into EL0 if keeping that code out of Zig improves clarity:

- load/set `SP_EL0`
- set `ELR_EL1`
- set `SPSR_EL1` for EL0t
- optionally restore initial user GPR state
- `ERET`

Do not put process policy or syscall dispatch in assembly.

### `secondary.S`

Owns the physical secondary-CPU trampoline:

- entry with MMU potentially off
- locate the logical CPU's prepared bootstrap descriptor
- set private stack
- normalize EL if required by the platform contract
- install translation tables / MMU state consistent with primary
- branch to common secondary Zig entry

Keep the trampoline in a region that remains physically reachable and identity mapped until all secondaries have booted.

## 2.6 Platform assembly responsibilities

Platform assembly is allowed only for things that cannot reasonably be deferred to Zig because no stack/runtime environment exists yet.

Examples:

- adapting a unique boot register convention
- parking unexpected CPUs if that platform's boot contract genuinely enters all PEs
- selecting a board-specific pre-stack temporary location
- jumping through a firmware-provided release trampoline

Not platform assembly:

- PL011 register programming
- GPIO configuration once Zig can run
- DT parsing
- ordinary interrupt-controller initialization

## 2.7 Compile-time platform selection

`build.zig` should parse one platform enum and derive everything else:

```text
-Dplatform=qemu_virt
-Dplatform=qemu_raspi3b
-Dplatform=qemu_raspi4b
-Dplatform=rpi3b
-Dplatform=rpi4b
-Dplatform=rpi5
```

The selected platform determines as one unit:

```text
AArch64 target CPU/features
platform Zig module
platform boot.S
platform linker script
raw-image rules
run command or boot-directory rules
early console fallback
runtime DT compatibility validation
```

Do not expose independent options that allow incompatible combinations such as `rpi4b` platform code with the `qemu_virt` linker script.

## 2.8 Architecture selection for future AArch32

Do not create `if (is_32_bit)` branches inside AArch64 assembly. A future port gets a parallel tree:

```text
src/arch/arm/
    asm/
    exceptions.zig
    mmu.zig
    ...

link/arm/kernel.ld
```

A future target can then be the composition:

```text
architecture = arm
platform     = rpi3b
```

while the initial system remains:

```text
architecture = aarch64
platform     = rpi3b
```
