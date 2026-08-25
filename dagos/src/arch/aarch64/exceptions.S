// =============================================================================
// Exceptions
// =============================================================================
.section .text.exceptions, "ax"

.extern exception_handler

/*
 * Exception frame:
 * x0..x30
 * sp
 * elr_el1
 * spsr_el1
 * esr_el1
 * far_el1
 * 36 registers -> 36 * 8 = 288
 * 288 % 16 = 0, 16-byte aligned
 */
.equ PT_REGS_SIZE, 0x120

.macro kernel_entry el:req
    // save x registers
    stp     x0, x1, [sp, #16 * 0]
    stp     x2, x3, [sp, #16 * 1]
    stp     x4, x5, [sp, #16 * 2]
    stp     x6, x7, [sp, #16 * 3]
    stp     x8, x9, [sp, #16 * 4]
    stp     x10, x11, [sp, #16 * 5]
    stp     x12, x13, [sp, #16 * 6]
    stp     x14, x15, [sp, #16 * 7]
    stp     x16, x17, [sp, #16 * 8]
    stp     x18, x19, [sp, #16 * 9]
    stp     x20, x21, [sp, #16 * 10]
    stp     x22, x23, [sp, #16 * 11]
    stp     x24, x25, [sp, #16 * 12]
    stp     x26, x27, [sp, #16 * 13]
    stp     x28, x29, [sp, #16 * 14]

    // restore and save interrupted sp
    .if \el == 0
        mrs     x21, sp_el0
    .else
        // in kernel_ventry we do sp - #PT_REGS_SIZE so original sp is at sp + #PT_REGS_SIZE
        add     x21, sp, #PT_REGS_SIZE
    .endif

    // combine saving of sp and x30 to be able to use stp
    stp     x30, x21, [sp, #16 * 15]

    // save hardware exception states
    mrs     x22, elr_el1
    mrs     x23, spsr_el1
    mrs     x24, esr_el1
    mrs     x25, far_el1

    stp     x22, x23, [sp, #16 * 16]
    stp     x24, x25, [sp, #16 * 17]

    // in total we use #16 * 18 = 288 bytes
.endm

.macro entry_handler el:req, ht:req, regsize:req, label:req
.global el\el\ht\()_\regsize\()_\label
.type el\el\ht\()_\regsize\()_\label, %function

el\el\ht\()_\regsize\()_\label:
    // save state
    kernel_entry \el

    // call with first arg sp
    mov     x0, sp
    bl      exception_handler

    // TODO: support for eret
    // we hang until we support recovery
1:
    wfe
    b       1b

.size el\el\ht\()_\regsize\()_\label, . - el\el\ht\()_\regsize\()_\label
.endm

.macro kernel_ventry el:req, ht:req, regsize:req, label:req
    .align 7 // 128-byte aligned
.Lventry_start\@:
    sub     sp, sp, #PT_REGS_SIZE // allocate exception frame

    b       el\el\ht\()_\regsize\()_\label

    // asserts each entry to be at most 128 bytes
    .org    .Lventry_start\@ + 128
.endm

/*
 * EL1 vector table
 */
.align 11 // must be aligned to 2048 bytes

.global vectors
.type vectors, %object

vectors:
    // el1t
    // current el using sp_el0
    // we don't support these but they need to exist
    kernel_ventry   1, t, 64, sync
    kernel_ventry   1, t, 64, irq
    kernel_ventry   1, t, 64, fiq
    kernel_ventry   1, t, 64, error

    // el1h
    // current el using sp_el1
    kernel_ventry   1, h, 64, sync
    kernel_ventry   1, h, 64, irq
    kernel_ventry   1, h, 64, fiq
    kernel_ventry   1, h, 64, error

    // lower el, aarch64
    // we don't support these but they need to exist
    kernel_ventry   0, t, 64, sync
    kernel_ventry   0, t, 64, irq
    kernel_ventry   0, t, 64, fiq
    kernel_ventry   0, t, 64, error

    // lower el, aarch32
    // we don't support these but they need to exist
    kernel_ventry   0, t, 32, sync
    kernel_ventry   0, t, 32, irq
    kernel_ventry   0, t, 32, fiq
    kernel_ventry   0, t, 32, error

.size vectors, . - vectors

// early exception handlers
entry_handler   1, t, 64, sync
entry_handler   1, t, 64, irq
entry_handler   1, t, 64, fiq
entry_handler   1, t, 64, error

entry_handler   1, h, 64, sync
entry_handler   1, h, 64, irq
entry_handler   1, h, 64, fiq
entry_handler   1, h, 64, error

entry_handler   0, t, 64, sync
entry_handler   0, t, 64, irq
entry_handler   0, t, 64, fiq
entry_handler   0, t, 64, error

entry_handler   0, t, 32, sync
entry_handler   0, t, 32, irq
entry_handler   0, t, 32, fiq
entry_handler   0, t, 32, error

// vim: set ai et sw=4 ts=4 sts=4 ft=asm
