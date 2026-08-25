use core::arch::global_asm;

global_asm!(include_str!("exceptions.S"));

use crate::arch::cpu::{self, Register};

#[repr(C)]
pub struct ExceptionFrame {
    x: [Register; 31],

    sp: Register,
    elr_el1: Register,
    spsr_el1: Register,
    esr_el1: Register,
    far_el1: Register,
}

const _: () = {
    assert!(core::mem::size_of::<ExceptionFrame>() == 0x120);
};

#[unsafe(no_mangle)]
pub extern "C" fn exception_handler() -> ! {
    cpu::halt();
}
