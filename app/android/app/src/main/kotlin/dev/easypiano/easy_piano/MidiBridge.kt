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
            for (n in MidiParser.notes(data, offset, count)) {
                main.post { sink?.success(listOf("n", n.pitch, n.velocity, if (n.on) 1 else 0, ms)) }
            }
        }
    }
}
