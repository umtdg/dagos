pub fn main() {
    println!("cargo:rustc-link-arg=-T../src/linker/qemu-virt.ld");
}
