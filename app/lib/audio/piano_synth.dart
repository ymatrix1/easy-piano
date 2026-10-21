import 'piano_synth_stub.dart'
    if (dart.library.js_interop) 'piano_synth_web.dart'
    as impl;

/// Sample-based piano and backing band (D22). Web uses Web Audio; other
/// platforms get a silent stub until the native audio engine lands
/// (docs/ARCHITECTURE.md).
abstract class PianoSynth {
  /// Whether the app plays piano sound. Off for digital pianos with their own
  /// speakers; on for MIDI controllers and the on-screen keyboard.
  bool get enabled;
  set enabled(bool value);

  /// Whether play-along clicks every beat, also under a companion part.
  /// Off still keeps the count-in. Remembered per device.
  bool get metronome;
  set metronome(bool value);

  /// Loads the piano samples. Safe to call more than once.
  Future<void> load();

  /// Loads the piano plus the band instruments that score [parts] (`DRUMS`,
  /// `BASS`, `PAD`, `CHOIR`) need; notes scheduled before then are silent.
  Future<void> loadParts(Iterable<String> parts);

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

  /// Schedules a sampled drum hit [startSec] seconds from now. [gmPitch]
  /// is a General MIDI percussion number: 36 kick, 38 snare, 42 closed hi-hat,
  /// 46 open hi-hat, 49 crash.
  void drum(int gmPitch, double startSec, {int velocity = 80});

  /// Schedules a sampled electric-bass note [startSec] seconds from now.
  void bass(int pitch, double startSec, double durSec, {int velocity = 80});

  /// Schedules a sampled string-ensemble note [startSec] seconds from now.
  void pad(int pitch, double startSec, double durSec, {int velocity = 80});

  /// Schedules a sampled wordless "ooh" choir voice [startSec] seconds from now.
  void choir(int pitch, double startSec, double durSec, {int velocity = 80});

  /// Sets a part's volume (1 = default mix level ... 0 = muted). [part] is a
  /// score part key (`ACC`, `DRUMS`, `BASS`, `PAD`, `CHOIR`) or `piano` for everything
  /// else on the piano voice.
  void setPartLevel(String part, double level);

  /// Stops everything scheduled or sounding.
  void stopAll();

  /// Web with `?mixprobe` in the URL: exposes `window.epMeasureMix()`, which renders
  /// [schedule] offline (all parts, then each part solo) and resolves to JSON
  /// with RMS and peak per part. Used for mix measurements; no-op elsewhere.
  void debugRegisterMixProbe(
    void Function(PianoSynth synth, double leadSec) schedule,
    double durSec,
  );
}

PianoSynth createPianoSynth() => impl.createPianoSynth();

/// The app's one piano voice (shared like the MIDI input).
final PianoSynth pianoSynth = createPianoSynth();
