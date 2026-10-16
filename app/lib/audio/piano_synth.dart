import 'piano_synth_stub.dart'
    if (dart.library.js_interop) 'piano_synth_web.dart'
    as impl;

/// Sample-based piano. Web uses Web Audio; other platforms get a silent stub
/// until the native audio engine lands (docs/ARCHITECTURE.md).
abstract class PianoSynth {
  /// Whether the app plays piano sound. Off for digital pianos with their own
  /// speakers; on for MIDI controllers and the on-screen keyboard.
  bool get enabled;
  set enabled(bool value);

  /// Loads the samples. Safe to call more than once.
  Future<void> load();

  /// Starts a note now (velocity 1–127).
  void noteOn(int pitch, {int velocity = 90});

  /// Releases a note with a short fade.
  void noteOff(int pitch);

  /// Schedules a note [startSec] seconds from now for [durSec] seconds; used by
  /// pre-listen. Plays even when [enabled] is false only if [force] is set.
  void schedule(
    int pitch,
    double startSec,
    double durSec, {
    int velocity = 80,
    bool force = false,
  });

  /// Schedules a metronome click [startSec] seconds from now (accent = beat 1).
  void click(double startSec, {bool accent = false});

  /// Stops everything scheduled or sounding.
  void stopAll();
}

PianoSynth createPianoSynth() => impl.createPianoSynth();

/// The app's one piano voice (shared like the MIDI input).
final PianoSynth pianoSynth = createPianoSynth();
