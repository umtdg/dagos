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

.equ CurrentEL_EL1, 0x4
.equ CurrentEL_EL2, 0x8

// Load the address of a symbol into  a register, PC-relative
.macro ADR_REL reg, sym
	adrp    \reg, \sym
	add     \reg, \reg, #:lo12:\sym
.endm

// =============================================================================
// fn _start()
// =============================================================================
_start:
	// if we are at EL1, jump straight to EL1 boot
	mrs     x0, CurrentEL
	cmp     x0, #CurrentEL_EL1
	b.eq    .L_boot_el1

	// if we are at EL2, jump to EL2 -> EL1 setup
	cmp     x0, #CurrentEL_EL2
	b.eq    .L_boot_el2

	// if we are here, then we are at EL3 or EL0, and we park
	b       .L_parking_loop

.L_boot_el2:
	// enable timer counters
	mov     x0, #0x3 // EL1PCTEN (bit 0) and EL1PCEN (bit 1)
	msr     CNTHCTL_EL2, x0

	// no offset for reading the counters
	msr     CNTVOFF_EL2, xzr

	// set HCR_EL2.RW = 1 (AArch64)
	mov     x0, #(1 << 31)
	msr     HCR_EL2, x0

	// DAIF (bits 6-9) = masked (1)
	// M[3:0] = 0b0101 = EL1h
	// 0b1111000000 | 0b0000000101
	mov     x0, #0x3c5
	msr     SPSR_EL2, x0

	adr     x0, .L_boot_el1
	msr     ELR_EL2, x0

	eret

.L_boot_el1:
	msr     SCTLR_EL1, xzr

	// Install exception handlers
	ADR_REL x0, vectors
	msr     VBAR_EL1, x0
	isb

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

	// Jump to Rust
	b       kmain

	// Infinitely wait for events
.L_parking_loop:
	wfe
	b       .L_parking_loop

.size   _start, . - _start
.type   _start, %function
.global _start
