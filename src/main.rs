#![no_std]
#![no_main]

use core::{arch::asm, panic::PanicInfo};

mod arch;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}

#[unsafe(no_mangle)]
fn kmain() -> ! {
    loop {
        unsafe {
            asm!("wfe");
        }
    }
}
