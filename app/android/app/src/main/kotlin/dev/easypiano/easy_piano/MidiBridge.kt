package dev.easypiano.easy_piano

import android.content.Context
import android.media.midi.MidiDevice
import android.media.midi.MidiDeviceInfo
import android.media.midi.MidiManager
import android.media.midi.MidiOutputPort
import android.media.midi.MidiReceiver
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * USB and BLE MIDI keyboards through android.media.midi. Every device that
 * has an output port (device -> app) is opened and its note on/off messages
 * are sent to Dart as `['n', pitch, velocity, on(1|0), ms]`, with `ms` on the
 * System.nanoTime clock. Device list changes come as `['d', name, ...]`.
 */
class MidiBridge(context: Context) : EventChannel.StreamHandler {
    private val manager = context.getSystemService(Context.MIDI_SERVICE) as? MidiManager
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private val open = HashMap<Int, Open>()

    private class Open(
        val device: MidiDevice,
        val ports: List<MidiOutputPort>,
        val name: String,
    )

    private val callback = object : MidiManager.DeviceCallback() {
        override fun onDeviceAdded(info: MidiDeviceInfo) = openDevice(info)
        override fun onDeviceRemoved(info: MidiDeviceInfo) = closeDevice(info.id)
    }

    val available: Boolean get() = manager != null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        val m = manager ?: return
        m.registerDeviceCallback(callback, main)
        for (info in m.devices) openDevice(info)
        publishNames()
    }

    override fun onCancel(arguments: Any?) {
        manager?.unregisterDeviceCallback(callback)
        for (id in open.keys.toList()) closeDevice(id)
        sink = null
    }

    private fun openDevice(info: MidiDeviceInfo) {
        if (info.outputPortCount == 0 || open.containsKey(info.id)) return
        val name = info.properties.getString(MidiDeviceInfo.PROPERTY_NAME)
            ?: info.properties.getString(MidiDeviceInfo.PROPERTY_PRODUCT)
            ?: "MIDI device ${info.id}"
        manager?.openDevice(info, { device ->
            if (device == null) return@openDevice
            if (open.containsKey(info.id)) {
                device.close()
                return@openDevice
            }
            val ports = (0 until info.outputPortCount).mapNotNull { i ->
                device.openOutputPort(i)?.also { it.connect(NoteReceiver()) }
            }
            open[info.id] = Open(device, ports, name)
            publishNames()
        }, main)
    }

    private fun closeDevice(id: Int) {
        val o = open.remove(id) ?: return
        o.ports.forEach { runCatching { it.close() } }
        runCatching { o.device.close() }
        publishNames()
    }

    private fun publishNames() {
        sink?.success(listOf<Any>("d") + open.values.map { it.name })
    }

    private inner class NoteReceiver : MidiReceiver() {
        override fun onSend(data: ByteArray, offset: Int, count: Int, timestamp: Long) {
            val ms = (if (timestamp == 0L) System.nanoTime() else timestamp) / 1e6
            var i = offset
            val end = offset + count
            while (i < end) {
                val status = data[i].toInt() and 0xFF
                if (status < 0x80) {
                    i++
                    continue
                }
                val kind = status and 0xF0
                val len = when (kind) {
                    0xC0, 0xD0 -> 2
                    0xF0 -> 1
                    else -> 3
                }
                if (i + len > end) break
                if ((kind == 0x90 || kind == 0x80) && len == 3) {
                    val pitch = data[i + 1].toInt() and 0x7F
                    val vel = data[i + 2].toInt() and 0x7F
                    val on = kind == 0x90 && vel > 0
                    main.post { sink?.success(listOf("n", pitch, vel, if (on) 1 else 0, ms)) }
                }
                i += len
            }
        }
    }
}
