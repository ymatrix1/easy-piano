import 'piano_synth.dart';

PianoSynth createPianoSynth() => _SilentSynth();

class _SilentSynth implements PianoSynth {
  @override
  bool enabled = true;

  @override
  Future<void> load() async {}

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
  }) {}

  @override
  void click(double startSec, {bool accent = false}) {}

  @override
  void stopAll() {}
}
