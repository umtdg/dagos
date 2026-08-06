// =============================================================================
// Context
// =============================================================================

// =============================================================================
// fn switch_context(*prev_sp, *const next_sp)
// =============================================================================
switch_context:
    // Save callee-saved registers onto the current process's stack.
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    stp     x25, x26, [sp, #-16]!
    stp     x27, x28, [sp, #-16]!
    stp     x29, x30, [sp, #-16]!

    // switch stack pointer to the next process's stack
    // *prev_sp = sp
    mov     x2, sp
    str     x2, [x0]

    // sp = *next_sp
    ldr     x2, [x1]
    mov     sp, x2

    // Load registers from the switched stack pointer
    ldp     x29, x30, [sp], #16
    ldp     x27, x28, [sp], #16
    ldp     x25, x26, [sp], #16
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16

    ret

.size   switch, . - switch_context
.type   switch_context, %function
.global switch_context

// vim: set ai et sw=4 ts=4 sts=4 ft=asm
