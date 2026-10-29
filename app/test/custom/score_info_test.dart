import 'dart:convert';

import 'package:easy_piano/custom/score_info.dart';
import 'package:flutter_test/flutter_test.dart';

String _song(
  List<Map<String, String>> bars, {
  String key = 'G',
  num bpm = 100,
  String time = '3/4',
}) => jsonEncode({
  'id': 's',
  'title': 'T',
  'composer': 'C',
  'bpm': bpm,
  'time': time,
  'key': key,
  'bars': bars,
});

void main() {
  test('reads key, tempo, meter and bar count', () {
    final info = ScoreInfo.fromSongJson(
      _song([
        {'RH': 'G4:4 A4:4 B4:4'},
        {'RH': 'C5:2 r:4'},
      ]),
    );
    expect(
      (info.key, info.bpm, info.timeSignature, info.bars),
      ('G', 100, '3/4', 2),
    );
  });

  test('hand split follows the hands present in the bars', () {
    final right = ScoreInfo.fromSongJson(
      _song([
        {'RH': 'C4:1'},
      ]),
    );
    final left = ScoreInfo.fromSongJson(
      _song([
        {'LH': 'C3:1'},
      ]),
    );
    final both = ScoreInfo.fromSongJson(
      _song([
        {'RH': 'C4:2', 'LH': 'C3:2'},
      ]),
    );
    expect((right.rightHand, right.leftHand), (true, false));
    expect((left.rightHand, left.leftHand), (false, true));
    expect((both.rightHand, both.leftHand), (true, true));
  });

  test('a hand that only rests does not count as played', () {
    // `import_score` writes `r:1` for the left hand of a one-staff score.
    final info = ScoreInfo.fromSongJson(
      _song([
        {'RH': 'C4:4 D4:4 E4:4', 'LH': 'r:1'},
      ]),
    );
    expect((info.rightHand, info.leftHand), (true, false));
  });

  test('a slow one-hand melody is beginner', () {
    final info = ScoreInfo.fromSongJson(
      _song([
        {'RH': 'C4:4 D4:4 E4:4'},
        {'RH': 'F4:4 G4:4 A4:4'},
      ]),
    );
    expect(info.level, ScoreLevel.beginner);
  });

  test(
    'a fast two-hand piece with a wide range and many notes is advanced',
    () {
      final bar = {
        'RH': 'C6:8 B5:8 A5:8 G#5:8 G5:8 F#5:8 F5:8 E5:8',
        'LH': 'C2:8 G2:8 C3:8 E3:8 G3:8 C4:8 E4:8 G4:8',
      };
      final info = ScoreInfo.fromSongJson(_song([bar, bar], bpm: 160));
      expect(info.level, ScoreLevel.advanced);
    },
  );

  test('a score with no bars does not divide by zero', () {
    final info = ScoreInfo.fromSongJson(_song(const []));
    expect((info.bars, info.level), (0, ScoreLevel.beginner));
  });
}
