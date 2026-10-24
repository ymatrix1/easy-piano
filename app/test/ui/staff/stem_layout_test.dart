import 'dart:math' as math;

import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:easy_piano/ui/staff/stem_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StemLayout middle-line rule', () {
    test('Treble middle line is B4 (diatonicStep 3)', () {
      final mid = StemLayout.middleLineStep(false);
      expect(mid, diatonicStep(71)); // B4
    });

    test('Treble notes on or above middle line point stem DOWN', () {
      // B4 (71) is middle line -> DOWN
      expect(StemLayout.computeStemDown(pitch: 71, onBass: false), isTrue);
      // C5 (72) is above middle line -> DOWN
      expect(StemLayout.computeStemDown(pitch: 72, onBass: false), isTrue);
      // G5 (79) is high -> DOWN
      expect(StemLayout.computeStemDown(pitch: 79, onBass: false), isTrue);
    });

    test('Treble notes below middle line point stem UP', () {
      // A4 (69) is below middle line -> UP (stemDown is false)
      expect(StemLayout.computeStemDown(pitch: 69, onBass: false), isFalse);
      // E4 (64) bottom line -> UP
      expect(StemLayout.computeStemDown(pitch: 64, onBass: false), isFalse);
      // C4 (60) middle C -> UP
      expect(StemLayout.computeStemDown(pitch: 60, onBass: false), isFalse);
    });

    test('Bass middle line is D3 (diatonicStep -11)', () {
      final mid = StemLayout.middleLineStep(true);
      expect(mid, diatonicStep(50)); // D3
    });

    test('Bass notes on or above middle line point stem DOWN', () {
      // D3 (50) is middle line -> DOWN
      expect(StemLayout.computeStemDown(pitch: 50, onBass: true), isTrue);
      // F3 (53) line 4 -> DOWN
      expect(StemLayout.computeStemDown(pitch: 53, onBass: true), isTrue);
      // A3 (57) top line -> DOWN
      expect(StemLayout.computeStemDown(pitch: 57, onBass: true), isTrue);
    });

    test('Bass notes below middle line point stem UP', () {
      // C3 (48) below middle line -> UP
      expect(StemLayout.computeStemDown(pitch: 48, onBass: true), isFalse);
      // G2 (43) bottom line -> UP
      expect(StemLayout.computeStemDown(pitch: 43, onBass: true), isFalse);
    });

    test('Explicit stemDown override is honored', () {
      // High C6 explicitly forced UP
      expect(
        StemLayout.computeStemDown(
          pitch: 84,
          onBass: false,
          explicitStemDown: false,
        ),
        isFalse,
      );
      // Low C4 explicitly forced DOWN
      expect(
        StemLayout.computeStemDown(
          pitch: 60,
          onBass: false,
          explicitStemDown: true,
        ),
        isTrue,
      );
    });

    test('Chord auto direction votes based on extreme notes distance', () {
      // Chord: C4 (60) and G5 (79).
      // Mid is B4 (step 3). C4 is step -4 (dist 7 below). G5 is step 8 (dist 5 above).
      // Distance below (7) > distance above (5) -> stem UP
      expect(
        StemLayout.computeStemDown(
          pitch: 60,
          onBass: false,
          chordPitches: const [60, 79],
        ),
        isFalse,
      );

      // Chord: E4 (64, step -2, dist 5 below) and C6 (84, step 11, dist 8 above).
      // Distance above (8) > distance below (5) -> stem DOWN
      expect(
        StemLayout.computeStemDown(
          pitch: 64,
          onBass: false,
          chordPitches: const [64, 84],
        ),
        isTrue,
      );
    });

    test('Grand staff (piano) defaults RH stems UP and LH stems DOWN', () {
      // In Rondo alla Turca, D5 (74), C5 (72), B5 (83) in treble on grand staff
      // point UP to stay clear of the LH accompaniment in the inter-staff gap.
      expect(
        StemLayout.computeStemDown(
          pitch: 74,
          onBass: false,
          isGrandStaff: true,
        ),
        isFalse,
      );
      expect(
        StemLayout.computeStemDown(
          pitch: 83,
          onBass: false,
          isGrandStaff: true,
        ),
        isFalse,
      );
      // LH chords/notes in bass staff point DOWN
      expect(
        StemLayout.computeStemDown(pitch: 57, onBass: true, isGrandStaff: true),
        isTrue,
      );
      // Explicit override is still honored on grand staff
      expect(
        StemLayout.computeStemDown(
          pitch: 74,
          onBass: false,
          isGrandStaff: true,
          explicitStemDown: true,
        ),
        isTrue,
      );
    });
  });

  group('StemLayout stem tip and ledger line elongation', () {
    const space = 10.0;
    const middleY = 100.0;

    test('Standard note inside staff gets space * 3.5 length', () {
      // Note sitting near middle line
      final tipDown = StemLayout.calcStemTipY(
        noteY: 90.0,
        stemDown: true,
        space: space,
        middleLineY: middleY,
      );
      expect(tipDown, 90.0 + space * 3.5); // 125.0

      final tipUp = StemLayout.calcStemTipY(
        noteY: 110.0,
        stemDown: false,
        space: space,
        middleLineY: middleY,
      );
      expect(tipUp, 110.0 - space * 3.5); // 75.0
    });

    test(
      'High note on ledger lines above staff extends stem DOWN to middle line',
      () {
        // High note at y = 40 (middleLineY = 100).
        // Nominal tip = 40 + 35 = 75, which is above middleLine (100).
        // Gould rule: tip must reach at least middleLineY (100).
        final tip = StemLayout.calcStemTipY(
          noteY: 40.0,
          stemDown: true,
          space: space,
          middleLineY: middleY,
        );
        expect(tip, middleY);
      },
    );

    test(
      'Low note on ledger lines below staff extends stem UP to middle line',
      () {
        // Low note at y = 160 (middleLineY = 100).
        // Nominal tip = 160 - 35 = 125, which is below middleLine (100).
        // Gould rule: tip must reach at least middleLineY (100).
        final tip = StemLayout.calcStemTipY(
          noteY: 160.0,
          stemDown: false,
          space: space,
          middleLineY: middleY,
        );
        expect(tip, middleY);
      },
    );
  });

  group('StemLayout horizontal attachment stemX', () {
    const space = 10.0;
    const noteheadX = 50.0;
    final strokeWidth = math.max(1.2, space * 0.1); // 1.2

    test('Downward stem attaches flush with left edge of notehead', () {
      final sx = StemLayout.stemX(
        noteheadX: noteheadX,
        stemDown: true,
        space: space,
      );
      // Line is centered at noteheadX + strokeWidth / 2 so left edge is at noteheadX
      expect(sx, noteheadX + strokeWidth / 2);
    });

    test(
      'Upward stem attaches flush with right edge of notehead (1.3 * space)',
      () {
        final sx = StemLayout.stemX(
          noteheadX: noteheadX,
          stemDown: false,
          space: space,
        );
        // Leland notehead width is 1.3 * space.
        // Line is centered at noteheadX + 1.3 * space - strokeWidth / 2
        expect(sx, noteheadX + space * 1.3 - strokeWidth / 2);
      },
    );
  });
}
