package dev.easypiano.easy_piano

import android.content.Context
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var mic: MicBridge? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // The Rust audio engine (cpal/Oboe) needs the JavaVM and an Android
        // Context; Dart's FFI load can't hand them over, so do it here first.
        System.loadLibrary("easy_piano_bridge")
        initAndroidContext(applicationContext)
        super.onCreate(savedInstanceState)
    }

    private external fun initAndroidContext(context: Context)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val midi = MidiBridge(this)
        val micBridge = MicBridge(this).also { mic = it }
        EventChannel(messenger, "dev.easypiano/midi/events").setStreamHandler(midi)
        EventChannel(messenger, "dev.easypiano/mic/events").setStreamHandler(micBridge)
        MethodChannel(messenger, "dev.easypiano/input").setMethodCallHandler { call, result ->
            when (call.method) {
                "clockMs" -> result.success(System.nanoTime() / 1e6)
                "midiAvailable" -> result.success(midi.available)
                "micPermission" -> micBridge.requestPermission(result)
                "micDevices" -> result.success(micBridge.devices())
                "micSelect" -> {
                    micBridge.deviceId = call.arguments as? Int
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        code: Int,
        permissions: Array<out String>,
        grants: IntArray,
    ) {
        super.onRequestPermissionsResult(code, permissions, grants)
        mic?.onPermissionResult(code, grants)
    }
}
