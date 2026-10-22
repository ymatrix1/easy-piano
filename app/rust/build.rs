// cpal reaches AAudio through Oboe, a C++ library built into this cdylib.
// Without the NDK's C++ runtime linked in, Android refuses to load the
// library (`cannot locate symbol "__cxa_pure_virtual"`), so link it statically.
fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
        println!("cargo:rustc-link-lib=c++_static");
        println!("cargo:rustc-link-lib=c++abi");
    }
}
