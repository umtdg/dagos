# 13. Assembly Blueprints

These are implementation blueprints for file boundaries and control flow. They are intentionally explicit about register ownership and stack rules. Exact system-register RES0/RES1 values must be derived from the Arm Architecture Reference Manual for the minimum architecture baseline selected by the build; do not replace named fields with unexplained copied constants.

## 13.1 Shared platform wrapper

All current targets can select the same wrapper after their DTB handoff contract is verified:

```asm
/* src/platform/common/asm/aarch64_dtb_boot.S */
.section .text.boot, "ax"
.balign 16

.global _start
.type _start, %function
_start:
    /*
     * Contract:
     *   x0 = DTB physical address for primary under configured boot path
     *   x1-x3 reserved/zero under Linux-style AArch64 handoff
     *
     * Do not touch them here. The common architecture entry preserves them.
     */
    b aarch64_boot_entry
.size _start, . - _start
```

Per-platform assembly is added only when a future platform genuinely differs before the architecture can establish a stack. The build still associates this shared source with each platform contract; sharing the file does not mean the contracts are undocumented.

## 13.2 `common.inc`

Keep macros small and transparent:

```asm
/* src/arch/aarch64/asm/include/common.inc */

.macro FUNC_BEGIN name
    .global \name
    .type \name, %function
    .balign 4
\name:
.endm

.macro FUNC_END name
    .size \name, . - \name
.endm

.macro LOAD_LINK_ADDR reg, sym
    adrp \reg, \sym
    add  \reg, \reg, :lo12:\sym
.endm
```

Do not hide long exception save/restore sequences in a generic macro if normal labels are easier to disassemble and debug. Use macros where they preserve a strict invariant, not to make assembly look shorter.

## 13.3 `entry.S`

The common primary entry can be structured as follows:

```asm
/* src/arch/aarch64/asm/entry.S */
#include "common.inc"

.extern __boot_stack_top
.extern __bss_start
.extern __bss_end
.extern aarch64_vectors
.extern arch_early_main

.section .text.boot, "ax"

FUNC_BEGIN aarch64_boot_entry
    /* Mask Debug, SError, IRQ and FIQ before touching shared state. */
    msr daifset, #0xf

    /* Preserve boot-protocol arguments without using memory. */
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x22, x3

    /* Preserve hardware identity and entry EL for diagnostics. */
    mrs x23, MPIDR_EL1
    mrs x24, CurrentEL

    /*
     * Select the current EL's handler stack before using SP.
     * At EL1 this selects SP_EL1; at EL2 it selects SP_EL2.
     */
    msr SPSel, #1
    LOAD_LINK_ADDR x9, __boot_stack_top
    and x9, x9, #-16
    mov sp, x9

    cmp x24, #0x8              /* CurrentEL encoding for EL2 */
    b.eq aarch64_drop_el2_to_el1

    cmp x24, #0x4              /* CurrentEL encoding for EL1 */
    b.eq aarch64_el1_entry

    b aarch64_unsupported_entry_el
FUNC_END aarch64_boot_entry

FUNC_BEGIN aarch64_el1_entry
    /* Ensure the normal kernel stack convention is EL1h / SP_EL1. */
    msr SPSel, #1
    LOAD_LINK_ADDR x9, __boot_stack_top
    and x9, x9, #-16
    mov sp, x9

    /* Install vectors early; asynchronous exceptions are still masked. */
    LOAD_LINK_ADDR x9, aarch64_vectors
    msr VBAR_EL1, x9
    isb

    /* Clear only BSS, never the active .boot_stack section. */
    LOAD_LINK_ADDR x9, __bss_start
    LOAD_LINK_ADDR x10, __bss_end
1:
    cmp x9, x10
    b.hs 2f
    stp xzr, xzr, [x9], #16
    b 1b
2:
    /* AAPCS64 argument registers for the first Zig function. */
    mov x0, x19                /* DTB PA */
    mov x1, x23                /* entry MPIDR */
    mov x2, x24                /* raw entry CurrentEL */
    bl arch_early_main

    /* arch_early_main is not expected to return during early bring-up. */
3:
    wfe
    b 3b
FUNC_END aarch64_el1_entry

FUNC_BEGIN aarch64_unsupported_entry_el
1:
    wfe
    b 1b
FUNC_END aarch64_unsupported_entry_el
```

### Important caveat: early synchronous faults

`VBAR_EL1` is installed before BSS clear so a synchronous fault does not vector through an undefined base. However the full Zig exception dispatcher must not assume BSS is initialized yet. Use one of these designs:

1. **Recommended:** a `.data`-initialized `exceptions_runtime_ready = 0` flag inspected by the common assembly dispatcher; if zero, branch to a GDB-visible early-fatal loop without calling Zig. Set it to 1 only after BSS and early console initialization.
2. Install a minimal separate early vector table first, then replace `VBAR_EL1` with the full table after BSS. This is robust but duplicates 2 KiB of vector slots.

The first design keeps one architectural table and one frame ABI.

## 13.4 `el.S`: EL2 → EL1h

A baseline structure:

```asm
/* src/arch/aarch64/asm/el.S */
#include "common.inc"

.extern __boot_stack_top
.extern aarch64_el1_entry

/* Named field definitions should live in sysreg.inc and cite the Arm ARM. */
.equ HCR_EL2_RW_ONLY, (1 << 31)
.equ CNTHCTL_EL2_EL1PCTEN, (1 << 0)
.equ CNTHCTL_EL2_EL1PCEN,  (1 << 1)
.equ CNTHCTL_EL2_DAGOS_BASELINE, (CNTHCTL_EL2_EL1PCTEN | CNTHCTL_EL2_EL1PCEN)
.equ SPSR_DAIF_MASK, (0xf << 6)
.equ SPSR_M_EL1H, 0x5
.equ SPSR_EL2_TO_EL1H, (SPSR_DAIF_MASK | SPSR_M_EL1H)

.section .text.boot, "ax"

FUNC_BEGIN aarch64_drop_el2_to_el1
    /*
     * Establish a classic, non-VHE EL2 policy for a normal EL1 kernel.
     * Do not preserve architecturally-UNKNOWN warm-reset trap bits.
     * The initial policy writes a known HCR value: lower EL executes
     * AArch64 and stage-2 translation/trap/routing features stay disabled.
     */
    mov x9, #HCR_EL2_RW_ONLY
    msr HCR_EL2, x9

    /*
     * With HCR_EL2.E2H == 0, the Armv8 baseline uses:
     *   EL1PCTEN = bit 0  -- do not trap EL1 physical-counter access
     *   EL1PCEN  = bit 1  -- do not trap EL1 physical-timer access
     * Preserve unrelated fields only if the platform contract requires it;
     * for Dagos' owned EL2->EL1 transition, use a named known baseline.
     */
    mov x9, #CNTHCTL_EL2_DAGOS_BASELINE
    msr CNTHCTL_EL2, x9
    msr CNTVOFF_EL2, xzr

    /*
     * Establish a documented little-endian MMU-off EL1 control value.
     * SCTLR_EL1 has feature-dependent/reset-UNKNOWN fields, so neither xzr
     * nor a copied tutorial literal is a long-term ABI. Generate/define
     * SCTLR_EL1_MMU_OFF_BASELINE from the minimum supported architecture
     * and feature policy, and keep M=0 and C=0 here. Linux'
     * INIT_SCTLR_EL1_MMU_OFF is a useful implementation reference.
     */
    ldr x9, =SCTLR_EL1_MMU_OFF_BASELINE
    msr SCTLR_EL1, x9

    /* Set the EL1h stack used immediately after ERET. */
    LOAD_LINK_ADDR x9, __boot_stack_top
    and x9, x9, #-16
    msr SP_EL1, x9

    adr x9, aarch64_el1_entry
    msr ELR_EL2, x9

    mov x9, #SPSR_EL2_TO_EL1H
    msr SPSR_EL2, x9

    isb
    eret
FUNC_END aarch64_drop_el2_to_el1
```

`HCR_EL2_RW_ONLY`, `CNTHCTL_EL2_DAGOS_BASELINE`, and `SCTLR_EL1_MMU_OFF_BASELINE` belong in `sysreg.inc` (or are generated from one architecture-constants source). The CNTHCTL bit numbers shown are the non-VHE Armv8 baseline [ARM-REGS]. Revisit this policy when enabling VHE or newer timer extensions rather than reusing it blindly. The Arm ARM is normative; Linux `head.S`/`sysreg.h` is a useful implementation cross-check [LINUX-ARM64-HEAD].

If kernel FP/SIMD is compiled out, do not enable it merely because an example startup file does. If it is enabled later, add deliberate trap/access configuration and context preservation.

## 13.5 Exception vector stub strategy without clobbering a GPR

A vector stub cannot safely do:

```asm
mov x0, #VECTOR_KIND
b common_handler
```

because the interrupted `x0` is lost before it is saved.

Instead each out-of-table thunk first allocates the frame and saves one scratch register:

```asm
/* conceptual thunk */
vector_sync_lower_a64:
    sub sp, sp, #EXC_FRAME_SIZE
    str x0, [sp, #EXC_X0]
    mov x0, #VECTOR_SYNC_LOWER_A64
    b exception_entry_x0_saved
```

The common routine receives vector kind in `x0`, while original `x0` already lives in the frame.

## 13.6 SP0 vectors need special treatment

If an exception is taken from the current EL while the kernel is using SP0, `SP` refers to `SP_EL0`. Dagos treats this as an invariant violation because kernel code is supposed to run EL1h.

Do not allocate a kernel exception frame on the possibly user-controlled SP0. The slot should first select `SP_EL1` without clobbering a GPR:

```asm
vector_slot_sync_current_sp0:
    msr SPSel, #1
    b vector_fatal_current_sp0
```

The fatal thunk can then allocate a frame on the known kernel `SP_EL1` stack.

## 13.7 `vectors.S` common save

With generated offsets:

```asm
#include "common.inc"
#include "exception_frame.inc"

.extern exception_dispatch

.section .text.vectors, "ax"
.balign 0x800
.global aarch64_vectors

aarch64_vectors:
    b slot_sync_current_sp0
    .balign 0x80
    b slot_irq_current_sp0
    .balign 0x80
    b slot_fiq_current_sp0
    .balign 0x80
    b slot_serror_current_sp0
    .balign 0x80

    b slot_sync_current_spx
    .balign 0x80
    b slot_irq_current_spx
    .balign 0x80
    b slot_fiq_current_spx
    .balign 0x80
    b slot_serror_current_spx
    .balign 0x80

    b slot_sync_lower_a64
    .balign 0x80
    b slot_irq_lower_a64
    .balign 0x80
    b slot_fiq_lower_a64
    .balign 0x80
    b slot_serror_lower_a64
    .balign 0x80

    b slot_sync_lower_a32
    .balign 0x80
    b slot_irq_lower_a32
    .balign 0x80
    b slot_fiq_lower_a32
    .balign 0x80
    b slot_serror_lower_a32
    .balign 0x80

aarch64_vectors_end:

/* One thunk per vector kind. Example: */
slot_sync_lower_a64:
    sub sp, sp, #EXC_FRAME_SIZE
    str x0, [sp, #EXC_X0]
    mov x0, #VECTOR_SYNC_LOWER_A64
    b exception_entry_x0_saved

exception_entry_x0_saved:
    /* x0 now contains VectorKind. Original x0 is already saved. */
    stp x1,  x2,  [sp, #EXC_X1]
    stp x3,  x4,  [sp, #EXC_X3]
    stp x5,  x6,  [sp, #EXC_X5]
    stp x7,  x8,  [sp, #EXC_X7]
    stp x9,  x10, [sp, #EXC_X9]
    stp x11, x12, [sp, #EXC_X11]
    stp x13, x14, [sp, #EXC_X13]
    stp x15, x16, [sp, #EXC_X15]
    stp x17, x18, [sp, #EXC_X17]
    stp x19, x20, [sp, #EXC_X19]
    stp x21, x22, [sp, #EXC_X21]
    stp x23, x24, [sp, #EXC_X23]
    stp x25, x26, [sp, #EXC_X25]
    stp x27, x28, [sp, #EXC_X27]
    stp x29, x30, [sp, #EXC_X29]

    str x0, [sp, #EXC_VECTOR]

    mrs x1, SP_EL0
    str x1, [sp, #EXC_SP_EL0]
    mrs x1, ELR_EL1
    str x1, [sp, #EXC_ELR]
    mrs x1, SPSR_EL1
    str x1, [sp, #EXC_SPSR]
    mrs x1, ESR_EL1
    str x1, [sp, #EXC_ESR]
    mrs x1, FAR_EL1
    str x1, [sp, #EXC_FAR]

    /* AAPCS64: x0 = pointer to frame. */
    mov x0, sp

    /* If runtime is not ready, branch to an assembly-only early fatal path. */
    bl exception_dispatch

.global aarch64_exception_restore
.type aarch64_exception_restore, %function
aarch64_exception_restore:
    /* Dispatcher may have modified return state. */
    ldr x16, [sp, #EXC_SP_EL0]
    msr SP_EL0, x16
    ldr x16, [sp, #EXC_ELR]
    msr ELR_EL1, x16
    ldr x16, [sp, #EXC_SPSR]
    msr SPSR_EL1, x16

    ldp x0,  x1,  [sp, #EXC_X0]
    ldp x2,  x3,  [sp, #EXC_X2]
    ldp x4,  x5,  [sp, #EXC_X4]
    ldp x6,  x7,  [sp, #EXC_X6]
    ldp x8,  x9,  [sp, #EXC_X8]
    ldp x10, x11, [sp, #EXC_X10]
    ldp x12, x13, [sp, #EXC_X12]
    ldp x14, x15, [sp, #EXC_X14]
    ldp x16, x17, [sp, #EXC_X16]
    ldp x18, x19, [sp, #EXC_X18]
    ldp x20, x21, [sp, #EXC_X20]
    ldp x22, x23, [sp, #EXC_X22]
    ldp x24, x25, [sp, #EXC_X24]
    ldp x26, x27, [sp, #EXC_X26]
    ldp x28, x29, [sp, #EXC_X28]
    ldr x30, [sp, #EXC_X30]

    add sp, sp, #EXC_FRAME_SIZE
    eret
```

The pairings above depend on generated offsets being contiguous exactly as designed. If the actual frame layout changes, regenerate the include and keep compile-time Zig assertions.

## 13.8 Initial EL0 entry can reuse the exception restore path

Instead of writing a second full GPR restore sequence, construct a synthetic `ExceptionFrame` on the task's kernel stack:

```text
x0-x30      initial user values
SP_EL0      user stack top
ELR_EL1     user entry PC
SPSR_EL1    EL0t state
```

Then use a tiny helper:

```asm
/* src/arch/aarch64/asm/user.S */
.extern aarch64_exception_restore

.global aarch64_enter_frame
.type aarch64_enter_frame, %function
aarch64_enter_frame:
    /* x0 must point to a validated ExceptionFrame on current kernel stack. */
    mov sp, x0
    b aarch64_exception_restore
```

This gives first entry and every subsequent exception return exactly one architectural restore/`ERET` implementation.

Before calling it, high-level code must have installed the process address space and ensured `SP_EL1`/the frame reside on the correct kernel stack.

## 13.9 Context switch blueprint

Do not double-reserve the stack. Either subtract 96 bytes once and store at fixed offsets, or use six pre-indexing `STP`s. This version uses the latter:

```asm
/* src/arch/aarch64/asm/context.S */
.text
.balign 4
.global switch_context
.type switch_context, %function
switch_context:
    /* x0 = &prev.saved_sp, x1 = &next.saved_sp */
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    stp x25, x26, [sp, #-16]!
    stp x27, x28, [sp, #-16]!
    stp x29, x30, [sp, #-16]!

    mov x2, sp
    str x2, [x0]

    ldr x2, [x1]
    mov sp, x2

    ldp x29, x30, [sp], #16
    ldp x27, x28, [sp], #16
    ldp x25, x26, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ret
.size switch_context, . - switch_context
```

Notice restore order is the reverse of save order. The synthetic new-task frame must use the same exact order.

If you prefer restoring `x19/x20` first, then store them at the lowest final stack address by changing save ordering. Pick one layout, document it, and test it.

## 13.10 Secondary entry blueprint

Do not route secondaries through `_start` and global initialization. A physical trampoline should do only bootstrap work:

```asm
/* src/arch/aarch64/asm/secondary.S */
#include "common.inc"

.global aarch64_secondary_entry
.type aarch64_secondary_entry, %function
aarch64_secondary_entry:
    msr daifset, #0xf
    mrs x19, MPIDR_EL1

    /*
     * Locate prebuilt SecondaryBootInfo by MPIDR using only registers and
     * physically reachable static memory. Do not use heap pointers here.
     */
    bl/branch assembly_scan_secondary_boot_info

    /* x20 now identifies the descriptor; load physical temporary stack. */
    ldr x9, [x20, #SECONDARY_BOOT_STACK_TOP_PHYS]
    and x9, x9, #-16
    msr SPSel, #1
    mov sp, x9

    /* Normalize EL if this platform contract can start secondaries at EL2. */
    mrs x9, CurrentEL
    cmp x9, #0x8
    b.eq secondary_drop_el2
    cmp x9, #0x4
    b.ne secondary_fatal

secondary_el1:
    /* Install common MAIR/TCR/TTBR state prepared by primary. */
    /* Call/branch common architecture MMU-enable routine. */
    /* Branch to high virtual continuation. */
    /* Switch to permanent high kernel stack. */
    /* Set high VBAR_EL1. */
    /* Call Zig secondary_main(logical_id, mpidr). */
```

The exact no-stack scan can be replaced by a platform/PSCI context register path if the startup ABI supplies a trusted descriptor index. Keep one common `SecondaryBootInfo` structure either way.

## 13.11 Why not put all assembly in one file

Separate files correspond to independent ABIs/mechanisms:

```text
entry.S      firmware/platform -> architecture runtime
el.S         EL2 -> EL1 contract
vectors.S    exception hardware -> ExceptionFrame ABI
user.S       ExceptionFrame -> EL0 architectural return
context.S    scheduler ABI -> saved kernel context
secondary.S  firmware CPU_ON/spin-table -> per-CPU runtime
```

They share constants/macros through `asm/include`, but each remains small enough to reason about in a disassembly. This gives reuse without creating a single monolithic startup file where boot, exceptions, scheduling, and SMP become inseparable.
