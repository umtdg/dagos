// =============================================================================
// Public code
// =============================================================================
.section .text._start, "ax"
.balign 4

.extern __bss
.extern __bss_end
.extern __stack_top
.extern kmain
.extern vectors // from exceptions.S

// Load the address of a symbol into  a register, PC-relative
.macro ADR_REL reg, sym
    adrp    \reg, \sym
    add     \reg, \reg, #:lo12:\sym
.endm

// =============================================================================
// fn _start()
// =============================================================================
_start:
    mrs     x0, CurrentEL
    cmp     x0, #0x4
    b.ne    .L_parking_loop

    // Mask async exceptions during early boot
    msr     daifset, #0xf

    // Use SP_EL1
    msr     SPSel, #1

    // Initialize DRAM
    ADR_REL x0, __bss
    ADR_REL x1, __bss_end

.L_bss_init_loop:
    cmp     x0, x1
    b.eq    .L_start_rust
    stp     xzr, xzr, [x0], #16
    b       .L_bss_init_loop

    // Prepare the jump to Rust code
.L_start_rust:
    // Prepare stack
    ADR_REL x0, __stack_top
    mov     sp, x0

    // Install exception handlers
    ADR_REL x0, vectors
    msr     VBAR_EL1, x0
    isb

    // Jump to Rust
    b       kmain

    // Infinitely wait for events
.L_parking_loop:
    wfe
    b       .L_parking_loop

.size   _start, . - _start
.type   _start, %function
.global _start

// vim: set ai et sw=4 ts=4 sts=4 ft=asm
