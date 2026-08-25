use crate::arch::asm;

pub const STACK_ALIGNMENT: usize = 16;

#[repr(transparent)]
pub struct Register(u64);

#[inline]
pub fn halt() -> ! {
    loop {
        asm::wfe();
    }
}
