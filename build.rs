pub fn main() {
    println!("cargo:rustc-link-arg=-Tsrc/linker/qemu-virt.ld");
}
