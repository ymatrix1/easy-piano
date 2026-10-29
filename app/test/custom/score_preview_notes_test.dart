import 'dart:typed_data';

import 'package:easy_piano/custom/score_preview_notes.dart';
import 'package:easy_piano/src/rust/api/practice.dart';
import 'package:easy_piano/ui/staff/song_rest_parser.dart';
import 'package:flutter_test/flutter_test.dart';

TargetView _target(double beat, List<int> pitches, {List<bool>? leftHands}) =>
    TargetView(
      beat: beat,
      beats: 1,
      bar: 0,
      pitches: Uint8List.fromList(pitches),
      fingers: Uint8List(0),
      stemDowns: const [],
      twoStems: const [],
      leftHands: leftHands ?? const [],
      noteBeats: Float64List.fromList([for (final _ in pitches) 1.0]),
      ties: const [],
      state: 0,
    );

void main() {
  test('targets become staff notes up to the beat limit', () {
    final notes = staffNotesFromTargets([
      _target(0, [60]),
      _target(1, [64, 48], leftHands: [false, true]),
      _target(4, [67]),
    ], maxBeats: 4);
    expect(notes.map((n) => (n.pitch, n.beat, n.leftHand)), [
      (60, 0.0, false),
      (64, 1.0, false),
      (48, 1.0, true),
    ]);
  });

  test('hand falls back to the pitch when the core gives none', () {
    final notes = staffNotesFromTargets([
      _target(0, [48, 72]),
    ], maxBeats: 4);
    expect(notes.map((n) => n.leftHand), [true, false]);
  });

  test('rests before the limit become rest notes on the right staff', () {
    final rests = staffRestsFrom(const [
      SongRest(beat: 0, beats: 1, leftHand: true, voice: 1),
      SongRest(beat: 5, beats: 1, leftHand: false, voice: 1),
    ], maxBeats: 4);
    expect(rests, hasLength(1));
    expect((rests.single.isRest, rests.single.leftHand), (true, true));
  });
}
