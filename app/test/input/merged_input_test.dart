import 'dart:async';

import 'package:easy_piano/input/merged_input.dart';
import 'package:easy_piano/input/midi_input.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fake implements MidiInput {
  final c = StreamController<NoteEvent>.broadcast();
  @override
  Stream<NoteEvent> get events => c.stream;
  @override
  List<String> get deviceNames => const [];
  @override
  Future<bool> start() async => true;
  @override
  double now() => 0;
}

NoteEvent _e(int p, bool on, double t) =>
    NoteEvent(pitch: p, velocity: 80, on: on, timestampMs: t);

void main() {
  test('MIDI and mic both pass; mic echo of a MIDI key is dropped', () async {
    final midi = _Fake(), mic = _Fake();
    final got = <String>[];
    final sub = MergedInput(
      midi,
      mic,
    ).events.listen((e) => got.add('${e.pitch}${e.on ? '+' : '-'}'));
    midi.c.add(_e(60, true, 1000));
    mic.c.add(_e(60, true, 1100)); // same key heard by the mic: echo
    mic.c.add(_e(60, false, 1500)); // its release is dropped too
    mic.c.add(_e(64, true, 1200)); // acoustic-only note: kept
    mic.c.add(_e(60, true, 3000)); // much later: a real re-strike
    await Future<void>.delayed(Duration.zero);
    expect(got, ['60+', '64+', '60+']);
    await sub.cancel();
  });
}
