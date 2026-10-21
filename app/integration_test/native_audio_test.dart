// Native sound through the Rust engine (D30 stage 2). Run on a device or
// desktop: flutter test integration_test/native_audio_test.dart -d windows
import 'package:easy_piano/audio/piano_synth.dart';
import 'package:easy_piano/src/rust/api/audio.dart';
import 'package:easy_piano/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  test('engine starts, loads the band and its clock runs', () async {
    final watch = Stopwatch()..start();
    await pianoSynth.loadParts(const ['DRUMS', 'BASS', 'PAD', 'CHOIR']);
    final loadMs = watch.elapsedMilliseconds;
    final info = await audioStart(); // already running: returns its info

    final t0 = audioNowSec();
    // A short phrase on every instrument, so the stream renders real voices.
    pianoSynth
      ..noteOn(60, velocity: 90)
      ..schedule(64, 0.05, 0.4, velocity: 70, part: 'ACC', force: true)
      ..drum(36, 0.05, velocity: 100)
      ..drum(42, 0.3, velocity: 60)
      ..bass(36, 0.05, 0.4)
      ..pad(60, 0.05, 0.6)
      ..choir(72, 0.05, 0.6)
      ..click(0.5, accent: true);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    pianoSynth.noteOff(60);
    final t1 = audioNowSec();

    // ignore: avoid_print
    print(
      'native audio: ${info.sampleRate} Hz, reported latency '
      '${info.latencyMs.toStringAsFixed(1)} ms, samples loaded in $loadMs ms, '
      'clock advanced ${((t1 - t0) * 1000).round()} ms over ~800 ms',
    );
    expect(info.sampleRate, greaterThan(0));
    expect(t1 - t0, inInclusiveRange(0.6, 1.2));
  });
}
