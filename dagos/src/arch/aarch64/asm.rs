use core::arch::asm;

#[inline]
pub fn nop() {
    unsafe {
        asm!("nop", options(nostack, nomem));
    }
}

#[inline]
pub fn wfe() {
    unsafe {
        asm!("wfe", options(nostack, nomem));
    }
}

pub fn udf<const IMM: usize>() {
    unsafe {
        asm!("udf #{imm}", imm = const IMM, options(nostack, nomem));
    }
}
