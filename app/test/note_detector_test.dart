import 'dart:math' as math;

import 'package:easy_piano/input/mic/note_detector.dart';
import 'package:easy_piano/practice/mic_setup.dart';
import 'package:flutter_test/flutter_test.dart';

const _sr = 48000.0;

/// Piano-like tone: 8 decaying partials with a 5 ms attack.
void _addNote(List<double> buf, double startSec, int pitch, double durSec) {
  final f0 = 440 * math.pow(2, (pitch - 69) / 12);
  final start = (startSec * _sr).round();
  final n = (durSec * _sr).round();
  for (var i = 0; i < n && start + i < buf.length; i++) {
    final t = i / _sr;
    final env = math.min(1.0, t / 0.005) * math.exp(-t * 2.5);
    var v = 0.0;
    for (var h = 1; h <= 8; h++) {
      v += math.sin(2 * math.pi * f0 * h * t) / (h * h * 0.7 + 0.3);
    }
    buf[start + i] += 0.15 * env * v;
  }
}

List<DetectedNote> _run(List<double> buf) {
  final det = NoteDetector(sampleRate: _sr);
  final out = <DetectedNote>[];
  for (var i = 0; i < buf.length; i += 128) {
    out.addAll(det.process(buf.sublist(i, math.min(i + 128, buf.length))));
  }
  return out.where((n) => n.on).toList();
}

void main() {
  test('single note: pitch and onset time', () {
    final buf = List<double>.filled((_sr * 1.5).round(), 0);
    _addNote(buf, 0.5, 60, 1.0);
    final ons = _run(buf);

    expect(ons.map((n) => n.pitch), [60]);
    expect(ons.single.time, closeTo(0.5, 0.01));
    // Reported after the analysis window, well inside core's mic window.
    expect(ons.single.detectedAt - 0.5, lessThan(0.15));
  });

  test('C major triad is found as three notes', () {
    final buf = List<double>.filled((_sr * 1.5).round(), 0);
    for (final p in [60, 64, 67]) {
      _addNote(buf, 0.4, p, 1.0);
    }

    expect(_run(buf).map((n) => n.pitch).toSet(), {60, 64, 67});
  });

  test('melody: each new note, not the ringing one', () {
    final buf = List<double>.filled((_sr * 2.5).round(), 0);
    const tune = [60, 62, 64, 65];
    for (var i = 0; i < tune.length; i++) {
      _addNote(buf, 0.3 + i * 0.5, tune[i], 0.9);
    }
    expect(_run(buf).map((n) => n.pitch).toList(), tune);
  });

  test('a held note is released within maxHold', () {
    final buf = List<double>.filled((_sr * 2.5).round(), 0);
    _addNote(buf, 0.3, 60, 2.2);
    final det = NoteDetector(sampleRate: _sr);
    final out = <DetectedNote>[];
    for (var i = 0; i < buf.length; i += 128) {
      out.addAll(det.process(buf.sublist(i, math.min(i + 128, buf.length))));
    }
    final off = out.firstWhere((n) => !n.on);
    expect(off.pitch, 60);
    expect(off.time - 0.3, lessThan(0.75));
  });

  List<DetectedNote> runExpecting(List<double> buf, Set<int> expected) {
    final det = NoteDetector(sampleRate: _sr)..expected = expected;
    final out = <DetectedNote>[];
    for (var i = 0; i < buf.length; i += 128) {
      out.addAll(det.process(buf.sublist(i, math.min(i + 128, buf.length))));
    }
    return out.where((n) => n.on).toList();
  }

  test('expected octave doubling is reported (blind mode drops it)', () {
    final buf = List<double>.filled((_sr * 1.5).round(), 0);
    _addNote(buf, 0.4, 60, 1.0);
    _addNote(buf, 0.4, 72, 1.0);
    final ons = runExpecting(buf, {60, 72});
    expect(ons.map((n) => n.pitch).toSet(), {60, 72});
    // Expected notes are checked every ~20 ms: reported well before the
    // ~100 ms analysis frame of the blind path.
    expect(ons.map((n) => n.detectedAt - 0.4).reduce(math.max), lessThan(0.1));
  });

  test('an expected note that is not played never fires', () {
    final rnd = math.Random(3);
    final buf = [
      for (var i = 0; i < _sr * 1.5; i++) (rnd.nextDouble() - 0.5) * 0.004,
    ];
    _addNote(buf, 0.4, 60, 1.0); // student plays C4
    final ons = runExpecting(buf, {62}); // lesson expects D4
    expect(ons.where((n) => n.pitch == 62), isEmpty);
    expect(ons.map((n) => n.pitch), contains(60));
  });

  test('typing clicks are not notes, even while a lesson waits', () {
    final rnd = math.Random(5);
    final buf = List<double>.filled((_sr * 3).round(), 0);
    // 4 ms bright noise bursts every ~150 ms, like a computer keyboard.
    for (var t = 0.3; t < 2.8; t += 0.12 + rnd.nextDouble() * 0.08) {
      final i = (t * _sr).round();
      for (var k = 0; k < _sr * 0.004; k++) {
        buf[i + k] +=
            (rnd.nextDouble() - 0.5) * 0.8 * math.exp(-k / (_sr * 0.0015));
      }
    }
    expect(runExpecting(buf, {60, 64, 67}), isEmpty);
  });

  test('silence and low noise give nothing', () {
    final rnd = math.Random(1);
    final buf = [
      for (var i = 0; i < _sr; i++) (rnd.nextDouble() - 0.5) * 0.002,
    ];
    expect(_run(buf), isEmpty);
  });

  test('calibration offset is the median of matched cues', () {
    final cues = <double>[1000, 1800, 2600, 3400, 4200, 5000];
    final onsets = <double>[1090, 1880, 2700, 3470, 4290, 9000];
    expect(calibrationOffset(cues, onsets), 90);
    expect(calibrationOffset(cues, const [1090.0, 1880.0]), isNull);
  });

  test('calibration accepts long latency (reaction + Bluetooth)', () {
    final cues = <double>[1000, 1800, 2600, 3400, 4200, 5000];
    final onsets = [for (final c in cues) c + 480];
    expect(calibrationOffset(cues, onsets), 480);
  });

  test('calibration rejects random taps', () {
    final cues = <double>[1000, 1800, 2600, 3400, 4200, 5000];
    final onsets = <double>[1010, 2100, 2650, 3900, 4250, 5500];
    expect(calibrationOffset(cues, onsets), isNull);
  });
}
