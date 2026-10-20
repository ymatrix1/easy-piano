import '../note_event.dart';
import 'mic_input_stub.dart'
    if (dart.library.js_interop) 'mic_input_web.dart'
    as impl;

/// Why the microphone could not start.
enum MicError { unsupported, denied }

/// Microphone note input. Emits the same [NoteEvent]s as MIDI, with
/// timestamps on the `performance.now()` clock already shifted by the
/// calibrated latency offset.
abstract class MicInput implements MidiInput {
  /// Set when [start] returned false.
  MicError? get error;

  /// Stops capture and releases the microphone.
  void stop();

  bool get running;

  /// Latency offset subtracted from every onset, in ms; null until the
  /// student calibrates. Remembered per device.
  double? get offsetMs;
  set offsetMs(double? value);

  /// Whether the student picked the microphone last time.
  bool get preferred;
  set preferred(bool value);

  /// Raw onsets (no offset applied), for the calibration step.
  Stream<NoteEvent> get rawEvents;
}

MicInput createMicInput() => impl.createMicInput();

/// The app's one microphone input (one capture graph per page).
final MicInput micInput = createMicInput();
