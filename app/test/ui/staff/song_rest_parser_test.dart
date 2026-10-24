import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:easy_piano/ui/staff/song_rest_parser.dart';

void main() {
  group('SongRestParser', () {
    test('parses basic rests in 4/4 time', () {
      final songJson = jsonEncode({
        'time': '4/4',
        'bars': [
          {'RH': 'r:4 C4:4 r:2'},
          {'LH': 'r:1'},
        ],
      });

      final rests = SongRestParser.parseRests(songJson);

      expect(rests.length, equals(3));

      // Bar 0 RH rests
      expect(rests[0].beat, equals(0.0));
      expect(rests[0].beats, equals(1.0));
      expect(rests[0].leftHand, isFalse);
      expect(rests[0].voice, equals(1));

      expect(rests[1].beat, equals(2.0)); // after r:4 (1.0) and C4:4 (1.0)
      expect(rests[1].beats, equals(2.0));
      expect(rests[1].leftHand, isFalse);

      // Bar 1 LH rest
      expect(rests[2].beat, equals(4.0)); // bar 1 start
      expect(rests[2].beats, equals(4.0));
      expect(rests[2].leftHand, isTrue);
      expect(rests[2].voice, equals(1));
    });

    test('parses dotted rests and eighth/sixteenth rests', () {
      final songJson = jsonEncode({
        'time': '4/4',
        'bars': [
          {'RH': 'r:4. C4:8 r:8 D4:8 r:16 E4:16'},
        ],
      });

      final rests = SongRestParser.parseRests(songJson);

      expect(rests.length, equals(3));
      expect(rests[0].beat, equals(0.0));
      expect(rests[0].beats, equals(1.5)); // dotted quarter = 1.5 beats

      expect(rests[1].beat, equals(2.0)); // 1.5 + 0.5
      expect(rests[1].beats, equals(0.5)); // eighth = 0.5 beat

      expect(rests[2].beat, equals(3.0)); // 2.0 + 0.5 + 0.5
      expect(rests[2].beats, equals(0.25)); // sixteenth = 0.25 beat
    });

    test('ignores non-piano tracks like ACC, DRUMS, BASS, PAD', () {
      final songJson = jsonEncode({
        'time': '4/4',
        'bars': [
          {
            'RH': 'r:4 C4:4',
            'ACC': 'r:1',
            'DRUMS': 'r:1',
            'BASS': 'r:1',
            'PAD': 'r:1',
          },
        ],
      });

      final rests = SongRestParser.parseRests(songJson);

      // Only the RH rest should be included!
      expect(rests.length, equals(1));
      expect(rests[0].leftHand, isFalse);
      expect(rests[0].beats, equals(1.0));
    });

    test('supports startBar and endBar pagination', () {
      final songJson = jsonEncode({
        'time': '4/4',
        'bars': [
          {'RH': 'r:1'},
          {'RH': 'r:1'},
          {'RH': 'r:1'},
        ],
      });

      final restsBar1 = SongRestParser.parseRests(
        songJson,
        startBar: 1,
        endBar: 2,
      );

      expect(restsBar1.length, equals(1));
      expect(restsBar1[0].beat, equals(4.0));
    });

    test('handles second voices (RH2, LH2)', () {
      final songJson = jsonEncode({
        'time': '4/4',
        'bars': [
          {'RH': 'C4:1', 'RH2': 'r:2 E4:2', 'LH2': 'r:1'},
        ],
      });

      final rests = SongRestParser.parseRests(songJson);

      expect(rests.length, equals(2));
      expect(rests[0].voice, equals(2));
      expect(rests[0].leftHand, isFalse);
      expect(rests[0].beats, equals(2.0));

      expect(rests[1].voice, equals(2));
      expect(rests[1].leftHand, isTrue);
      expect(rests[1].beats, equals(4.0));
    });
  });
}
