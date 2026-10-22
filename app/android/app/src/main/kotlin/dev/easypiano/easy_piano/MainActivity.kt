package dev.easypiano.easy_piano

import android.content.Context
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // The Rust audio engine (cpal/Oboe) needs the JavaVM and an Android
        // Context; Dart's FFI load can't hand them over, so do it here first.
        System.loadLibrary("easy_piano_bridge")
        initAndroidContext(applicationContext)
        super.onCreate(savedInstanceState)
    }

    private external fun initAndroidContext(context: Context)
}
