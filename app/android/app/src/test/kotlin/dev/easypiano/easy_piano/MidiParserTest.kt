package dev.easypiano.easy_piano

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MidiParserTest {
    private fun bytes(vararg v: Int) = ByteArray(v.size) { v[it].toByte() }

    @Test
    fun noteOnAndOff() {
        val b = bytes(0x90, 60, 100, 0x80, 60, 0)
        assertEquals(
            listOf(MidiNote(60, 100, true), MidiNote(60, 0, false)),
            MidiParser.notes(b, 0, b.size),
        )
    }

    @Test
    fun noteOnWithZeroVelocityIsOff() {
        val b = bytes(0x93, 72, 0)
        assertEquals(listOf(MidiNote(72, 0, false)), MidiParser.notes(b, 0, 3))
    }

    @Test
    fun skipsOtherMessagesAndStrayData() {
        val b = bytes(0xC0, 5, 0x7F, 0x91, 64, 80, 0xB0, 7, 99)
        assertEquals(listOf(MidiNote(64, 80, true)), MidiParser.notes(b, 0, b.size))
    }

    @Test
    fun honoursOffsetAndCount() {
        val b = bytes(0x90, 1, 1, 0x90, 62, 90, 0x90, 2, 2)
        assertEquals(listOf(MidiNote(62, 90, true)), MidiParser.notes(b, 3, 3))
    }

    @Test
    fun truncatedTrailingMessageIsDropped() {
        val b = bytes(0x90, 60, 100, 0x90, 61)
        assertEquals(listOf(MidiNote(60, 100, true)), MidiParser.notes(b, 0, b.size))
    }

    @Test
    fun emptyBuffer() {
        assertTrue(MidiParser.notes(ByteArray(0), 0, 0).isEmpty())
    }
}
