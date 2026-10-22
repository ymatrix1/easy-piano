//! Hands the JavaVM and application Context to ndk-context, which cpal's
//! Oboe host reads when it opens a stream. Called once from MainActivity.

use jni::objects::{JClass, JObject};
use jni::JNIEnv;

#[no_mangle]
pub extern "system" fn Java_dev_easypiano_easy_1piano_MainActivity_initAndroidContext(
    env: JNIEnv,
    _class: JClass,
    context: JObject,
) {
    let Ok(vm) = env.get_java_vm() else { return };
    let Ok(context) = env.new_global_ref(context) else {
        return;
    };
    // The global ref lives for the whole process, like the context itself.
    let ctx = context.as_obj().as_raw();
    std::mem::forget(context);
    unsafe { ndk_context::initialize_android_context(vm.get_java_vm_pointer().cast(), ctx.cast()) };
}
