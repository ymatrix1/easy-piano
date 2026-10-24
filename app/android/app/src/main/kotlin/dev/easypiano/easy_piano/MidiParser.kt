package dev.easypiano.easy_piano

/** One note on/off decoded from a MIDI byte stream. */
data class MidiNote(val pitch: Int, val velocity: Int, val on: Boolean)

/**
 * Pulls note on/off messages out of a raw MIDI buffer, skipping everything
 * else (program change, sysex start, stray data bytes) and tolerating several
 * messages in one packet or a truncated trailing one. A note-on with
 * velocity 0 is a note-off.
 */
object MidiParser {
    fun notes(data: ByteArray, offset: Int, count: Int): List<MidiNote> {
        val out = ArrayList<MidiNote>()
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
                val vel = data[i + 2].toInt() and 0x7F
                out.add(MidiNote(data[i + 1].toInt() and 0x7F, vel, kind == 0x90 && vel > 0))
            }
            i += len
        }
        return out
    }
}
