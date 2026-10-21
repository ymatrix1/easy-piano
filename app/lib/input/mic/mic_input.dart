import '../note_event.dart';
import 'mic_input_stub.dart'
    if (dart.library.js_interop) 'mic_input_web.dart'
    as impl;

/// An audio input the browser offers.
class MicDevice {
  const MicDevice(this.id, this.label);
  final String id;
  final String label;
}

/// Why the microphone could not start.
enum MicError {
  /// No getUserMedia / AudioWorklet in this browser.
  unsupported,

  /// The student or the browser blocked access (NotAllowedError,
  /// SecurityError).
  denied,

  /// No input, or the chosen one is gone (NotFoundError,
  /// OverconstrainedError).
  notFound,

  /// The device exists but can't be opened, often another app holds it
  /// (NotReadableError, AbortError).
  busy,
}

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
  /// student calibrates this input. Stored per input device (each mic or
  /// interface has its own latency) on this browser.
  double? get offsetMs;
  set offsetMs(double? value);

  /// Whether the student picked the microphone last time.
  bool get preferred;
  set preferred(bool value);

  /// Raw onsets (no offset applied), for the calibration step.
  Stream<NoteEvent> get rawEvents;

  /// Audio inputs; labels appear once permission was granted.
  Future<List<MicDevice>> devices();

  /// Chosen input id (null = browser default). Setting it while running
  /// restarts capture on that device. Remembered per device.
  String? get deviceId;
  Future<void> selectDevice(String? id);

  /// Input level 0–1 of the last ~50 ms, for the level meter.
  double get level;
}

MicInput createMicInput() => impl.createMicInput();

/// The app's one microphone input (one capture graph per page).
final MicInput micInput = createMicInput();

/// Maps a getUserMedia DOMException name to the error shown to the student.
MicError micErrorFor(String domExceptionName) => switch (domExceptionName) {
  'NotAllowedError' || 'SecurityError' => MicError.denied,
  'NotFoundError' || 'OverconstrainedError' => MicError.notFound,
  'NotReadableError' || 'AbortError' => MicError.busy,
  _ => MicError.unsupported,
};
