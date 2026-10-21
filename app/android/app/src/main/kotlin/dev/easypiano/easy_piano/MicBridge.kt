package dev.easypiano.easy_piano

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Microphone capture for note detection. Streams mono float PCM chunks to
 * Dart as `{sampleRate, endMs, samples: Float32 bytes}` with `endMs` on the
 * System.nanoTime clock; the detector itself runs in Dart, as on web.
 */
class MicBridge(private val activity: Activity) : EventChannel.StreamHandler {
    companion object {
        const val REQUEST_CODE = 4711
        private const val RATE = 44100
        private const val CHUNK = 1024
    }

    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var sink: EventChannel.EventSink? = null
    private var record: AudioRecord? = null
    private var thread: Thread? = null
    var deviceId: Int? = null

    private val audio get() = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    fun hasPermission() =
        activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    /** Result is "granted" or "denied". */
    fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission()) return result.success("granted")
        if (pending != null) return result.error("busy", "request in flight", null)
        pending = result
        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_CODE)
    }

    fun onPermissionResult(code: Int, grants: IntArray) {
        if (code != REQUEST_CODE) return
        val r = pending ?: return
        pending = null
        r.success(if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) "granted" else "denied")
    }

    fun devices(): List<Map<String, Any>> =
        audio.getDevices(AudioManager.GET_DEVICES_INPUTS)
            .filter { it.type != AudioDeviceInfo.TYPE_TELEPHONY }
            .map { mapOf("id" to it.id, "label" to deviceLabel(it)) }

    private fun deviceLabel(d: AudioDeviceInfo): String {
        val name = d.productName?.toString().orEmpty()
        val kind = when (d.type) {
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> "Built-in microphone"
            AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET -> "USB audio"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Headset"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth"
            else -> "Microphone"
        }
        return if (name.isEmpty() || name == kind) kind else "$kind ($name)"
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        if (!hasPermission()) {
            events.error("denied", "RECORD_AUDIO not granted", null)
            return
        }
        val min = AudioRecord.getMinBufferSize(
            RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT,
        )
        if (min <= 0) {
            events.error("unsupported", "no float capture", null)
            return
        }
        // Raw signal: processing smears piano attacks (same reasoning as web).
        val unprocessed =
            audio.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED) == "true"
        val source = if (unprocessed) MediaRecorder.AudioSource.UNPROCESSED else MediaRecorder.AudioSource.MIC
        val rec = try {
            AudioRecord.Builder()
                .setAudioSource(source)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                        .setSampleRate(RATE)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                        .build(),
                )
                .setBufferSizeInBytes(maxOf(min, CHUNK * 4 * 4))
                .build()
        } catch (e: Exception) {
            events.error("busy", e.message, null)
            return
        }
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            rec.release()
            events.error("busy", "AudioRecord not initialised", null)
            return
        }
        deviceId?.let { id ->
            audio.getDevices(AudioManager.GET_DEVICES_INPUTS).firstOrNull { it.id == id }
                ?.let { rec.preferredDevice = it }
        }
        record = rec
        rec.startRecording()
        thread = Thread {
            val buf = FloatArray(CHUNK)
            while (!Thread.currentThread().isInterrupted &&
                rec.recordingState == AudioRecord.RECORDSTATE_RECORDING
            ) {
                val n = rec.read(buf, 0, CHUNK, AudioRecord.READ_BLOCKING)
                if (n <= 0) break
                val bytes = ByteBuffer.allocate(n * 4).order(ByteOrder.nativeOrder())
                bytes.asFloatBuffer().put(buf, 0, n)
                val endMs = System.nanoTime() / 1e6
                val msg = mapOf("sampleRate" to RATE, "endMs" to endMs, "samples" to bytes.array())
                main.post { sink?.success(msg) }
            }
        }.also {
            it.name = "mic-capture"
            it.start()
        }
    }

    override fun onCancel(arguments: Any?) {
        thread?.interrupt()
        thread = null
        record?.let {
            runCatching { it.stop() }
            it.release()
        }
        record = null
        sink = null
    }
}
