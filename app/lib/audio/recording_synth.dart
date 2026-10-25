import 'piano_synth.dart';

/// A silent [PianoSynth] that records what it is asked to play, as plain
/// maps. Used to export play-along event fixtures for the Rust audio engine's
/// parity test (`audio/tests/`, D30).
class RecordingSynth implements PianoSynth {
  final events = <Map<String, Object>>[];

  @override
  bool enabled = true;

  @override
  bool metronome = true;

  @override
  Future<void> load() async {}

  @override
  Future<void> loadParts(Iterable<String> parts) async {}

  @override
  void noteOn(int pitch, {int velocity = 90}) {}

  @override
  void noteOff(int pitch) {}

  @override
  void schedule(
    int pitch,
    double startSec,
    double durSec, {
    int velocity = 80,
    bool force = false,
    String part = 'piano',
  }) => _add('piano', part, pitch, startSec, durSec, velocity);

  @override
  void click(double startSec, {bool accent = false}) =>
      _add('click', 'click', accent ? 1 : 0, startSec, 0, 0);

  @override
  void drum(int gmPitch, double startSec, {int velocity = 80}) =>
      _add('drum', 'DRUMS', gmPitch, startSec, 0, velocity);

  @override
  void bass(int pitch, double startSec, double durSec, {int velocity = 80}) =>
      _add('bass', 'BASS', pitch, startSec, durSec, velocity);

  @override
  void pad(int pitch, double startSec, double durSec, {int velocity = 80}) =>
      _add('strings', 'PAD', pitch, startSec, durSec, velocity);

  @override
  void choir(int pitch, double startSec, double durSec, {int velocity = 80}) =>
      _add('choir', 'CHOIR', pitch, startSec, durSec, velocity);

  void _add(
    String instrument,
    String part,
    int pitch,
    double startSec,
    double durSec,
    int velocity,
  ) => events.add({
    'instrument': instrument,
    'part': part,
    'pitch': pitch,
    'start': startSec,
    'dur': durSec,
    'velocity': velocity,
  });

  @override
  void setPartLevel(String part, double level) {}

  @override
  void stopAll() {}

  @override
  Future<void> resumeAudio() async {}

  @override
  set onStateChange(void Function()? callback) {}

  @override
  void debugRegisterMixProbe(
    void Function(PianoSynth synth, double leadSec) schedule,
    double durSec,
  ) {}
}
