OUTPUT_ARCH("aarch64")
ENTRY(_start)

SECTIONS {
    . = 0x40080000; /* base address */

    /* program code */
    .text : ALIGN(4) {
        KEEP(*(.text._start));
        *(.text*);
    }

    /* read-only constant data */
    .rodata : ALIGN(8) { *(.rodata*) }

    /* read-write data */
    .data : { *(.data*) }

    /*
     * zero-initialized read-write data
     *
     * ALIGN(16) is to allow use of `stp` when clearing bss
     */
    .bss (NOLOAD) : ALIGN(16) {
        __bss = .;

        *(.bss .bss.* .sbss .sbss.*);

        . = ALIGN(16);
        __bss_end = .;
    }

    /* kernel stack - 128K */
    .stack (NOLOAD) : ALIGN(16) {
        __stack_bottom = .;

        . += 128 * 1024;

        . = ALIGN(16);
        __stack_top = .;
    }

    /* memory - 64M */
    .memory (NOLOAD) : ALIGN(4096) {
        __free_mem = .;

        . += 64 * 1024 * 1024;

        . = ALIGN(4096);
        __free_mem_end = .;
    }
}
