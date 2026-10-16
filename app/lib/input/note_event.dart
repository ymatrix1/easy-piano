/// A key press or release from any input source.
class NoteEvent {
  const NoteEvent({
    required this.pitch,
    required this.velocity,
    required this.on,
    required this.timestampMs,
  });

  /// MIDI note number (60 = middle C).
  final int pitch;
  final int velocity;
  final bool on;

  /// Event time on the `performance.now()` clock (web) or monotonic clock.
  final double timestampMs;
}

/// Source of note events (Web MIDI, native MIDI, touch).
abstract class MidiInput {
  Stream<NoteEvent> get events;

  /// Names of connected input devices.
  List<String> get deviceNames;

  /// Requests access and starts listening. Returns false when unsupported or denied.
  Future<bool> start();

  /// Current time on the same clock as [NoteEvent.timestampMs].
  double now();
}
