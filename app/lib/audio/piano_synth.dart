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

  /// Whether play-along clicks every beat, also under a companion part.
  /// Off still keeps the count-in. Remembered per device.
  bool get metronome;
  set metronome(bool value);

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
    String part = 'piano',
  });

  /// Schedules a metronome click [startSec] seconds from now (accent = beat 1).
  void click(double startSec, {bool accent = false});

  /// Schedules a synthesized drum hit [startSec] seconds from now. [gmPitch]
  /// is a General MIDI percussion number: 36 kick, 38 snare, 42 closed hi-hat,
  /// 46 open hi-hat, 49 crash.
  void drum(int gmPitch, double startSec, {int velocity = 80});

  /// Schedules a synthesized bass note [startSec] seconds from now.
  void bass(int pitch, double startSec, double durSec, {int velocity = 80});

  /// Schedules a synthesized strings-pad note [startSec] seconds from now.
  void pad(int pitch, double startSec, double durSec, {int velocity = 80});

  /// Schedules a synthesized wordless "ooh" voice [startSec] seconds from now.
  void choir(int pitch, double startSec, double durSec, {int velocity = 80});

  /// Sets a part's volume (1 = default mix level ... 0 = muted). [part] is a
  /// score part key (`ACC`, `DRUMS`, `BASS`, `PAD`, `CHOIR`) or `piano` for everything
  /// else on the piano voice.
  void setPartLevel(String part, double level);

  /// Stops everything scheduled or sounding.
  void stopAll();
}

PianoSynth createPianoSynth() => impl.createPianoSynth();

/// The app's one piano voice (shared like the MIDI input).
final PianoSynth pianoSynth = createPianoSynth();
