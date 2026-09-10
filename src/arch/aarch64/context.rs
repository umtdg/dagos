use core::arch::global_asm;

global_asm!(include_str!("context.S"));

unsafe extern "C" {
    pub fn switch_context(prev_sp: *mut usize, next_s: *const usize);
}
