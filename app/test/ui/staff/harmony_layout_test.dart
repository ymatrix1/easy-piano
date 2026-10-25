import 'package:easy_piano/ui/staff/harmony_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChordSymbol.parse', () {
    test('root, suffix and bass are split', () {
      final c = ChordSymbol.parse('C');
      expect(c?.root, 'C');
      expect(c?.suffix, '');
      expect(c?.bass, isNull);

      final am7 = ChordSymbol.parse('Am7');
      expect(am7?.root, 'A');
      expect(am7?.suffix, 'm7');
      expect(am7?.bass, isNull);

      final g7b = ChordSymbol.parse('G7/B');
      expect(g7b?.root, 'G');
      expect(g7b?.suffix, '7');
      expect(g7b?.bass, 'B');

      final half = ChordSymbol.parse('F#m7b5');
      expect(half?.root, 'F#');
      expect(half?.suffix, 'm7b5');
    });

    test('a flat root is not mistaken for a suffix', () {
      final bb = ChordSymbol.parse('Bb');
      expect(bb?.root, 'Bb');
      expect(bb?.suffix, '');

      final bbm = ChordSymbol.parse('Bbm7/Db');
      expect(bbm?.root, 'Bb');
      expect(bbm?.suffix, 'm7');
      expect(bbm?.bass, 'Db');
    });

    test('altered and extended suffixes are kept', () {
      expect(ChordSymbol.parse('C#')?.root, 'C#');
      expect(ChordSymbol.parse('Cmaj7(#11)')?.suffix, 'maj7(#11)');
      expect(ChordSymbol.parse('Bdim7')?.suffix, 'dim7');
      expect(ChordSymbol.parse('C+')?.suffix, '+');
    });

    test('bad input gives null', () {
      for (final text in [
        '',
        'c',
        'H',
        'Am7 ',
        'C G',
        'C/',
        'C/H',
        'C/G/B',
        'G7/B7',
        'C{',
        'Cm7' * 6,
      ]) {
        expect(ChordSymbol.parse(text), isNull, reason: '"$text"');
      }
    });
  });

  group('HarmonyLayout chord geometry', () {
    test('runs: extension raised, bass lowered and smaller', () {
      final runs = HarmonyLayout.chordRuns(ChordSymbol.parse('G7/B')!);
      expect(runs.map((r) => r.text), ['G', '7', '/', 'B']);
      expect(runs[0].scale, 1);
      expect(runs[0].riseEm, 0);
      expect(runs[1].scale, HarmonyLayout.suffixScale);
      expect(runs[1].riseEm, greaterThan(0));
      expect(runs[2].riseEm, 0);
      expect(runs[3].scale, HarmonyLayout.bassScale);
      expect(runs[3].riseEm, lessThan(0));
    });

    test('a plain chord is one run', () {
      final runs = HarmonyLayout.chordRuns(ChordSymbol.parse('C')!);
      expect(runs.map((r) => r.text), ['C']);
    });

    test('baseline sits above the top staff line', () {
      expect(
        HarmonyLayout.chordBaselineY(staffTopY: 100, space: 10),
        100 - HarmonyLayout.chordGapSp * 10,
      );
    });

    test('a notehead higher than the staff line lifts the baseline', () {
      expect(
        HarmonyLayout.chordBaselineY(staffTopY: 100, noteTopY: 70, space: 10),
        70 - HarmonyLayout.chordGapSp * 10,
      );
      // A notehead lower than the staff line does not move it.
      expect(
        HarmonyLayout.chordBaselineY(staffTopY: 100, noteTopY: 120, space: 10),
        100 - HarmonyLayout.chordGapSp * 10,
      );
    });
  });

  group('StaffLyric.fromDirective', () {
    test('a syllable keeps its text', () {
      final l = StaffLyric.fromDirective(2, 'lo');
      expect(l?.beat, 2);
      expect(l?.text, 'lo');
      expect(l?.hyphen, isFalse);
      expect(l?.isExtension, isFalse);
      expect(l?.leftHand, isFalse);
    });

    test('a trailing hyphen marks a word break after the syllable', () {
      final l = StaffLyric.fromDirective(0, 'Hel-');
      expect(l?.text, 'Hel');
      expect(l?.hyphen, isTrue);
    });

    test('an underscore is an extension', () {
      final l = StaffLyric.fromDirective(1, '_', leftHand: true);
      expect(l?.isExtension, isTrue);
      expect(l?.leftHand, isTrue);
    });

    test('bad text gives null', () {
      for (final text in ['', '-', 'a b', 'a_b', 'a-b', '_-', 'a"', 'a{b']) {
        expect(StaffLyric.fromDirective(0, text), isNull, reason: '"$text"');
      }
    });
  });

  group('HarmonyLayout lyric geometry', () {
    test('a lyric is centred on its notehead centre', () {
      expect(HarmonyLayout.lyricLeft(centreX: 100, width: 40), 80);
    });

    test('the row sits below the staff, lower when notes reach it', () {
      const space = 10.0;
      expect(
        HarmonyLayout.lyricTop(staffBottomY: 200, space: space),
        200 + HarmonyLayout.lyricTopSp * space,
      );
      // Ink above the nominal row: no change.
      expect(
        HarmonyLayout.lyricTop(
          staffBottomY: 200,
          lowestInkY: 205,
          space: space,
        ),
        200 + HarmonyLayout.lyricTopSp * space,
      );
      // A stem reaching 215 pushes the row below it.
      expect(
        HarmonyLayout.lyricTop(
          staffBottomY: 200,
          lowestInkY: 215,
          space: space,
        ),
        215 + HarmonyLayout.lyricMinDistSp * space,
      );
    });

    test('a hyphen is centred between the two syllables', () {
      final seg = HarmonyLayout.hyphenSegment(
        prevRight: 100,
        nextLeft: 130,
        space: 10,
      );
      // Gap 30 minus 2 pads of 1 leaves 28; the hyphen is capped at 5.
      expect(seg, isNotNull);
      expect(seg!.x1 - seg.x0, closeTo(5, 1e-9));
      expect((seg.x0 + seg.x1) / 2, closeTo(115, 1e-9));
    });

    test('no hyphen when the gap is too small', () {
      expect(
        HarmonyLayout.hyphenSegment(prevRight: 100, nextLeft: 103, space: 10),
        isNull,
      );
    });

    test('a melisma line is padded at both ends', () {
      final seg = HarmonyLayout.dashSegment(fromX: 100, toX: 140, space: 10);
      expect(seg, isNotNull);
      expect(seg!.x0, closeTo(102, 1e-9));
      expect(seg.x1, closeTo(138, 1e-9));
    });

    test('a melisma line shorter than its minimum is not drawn', () {
      expect(
        HarmonyLayout.dashSegment(fromX: 100, toX: 105, space: 10),
        isNull,
      );
    });

    test('hyphens and melisma lines sit above the lyric baseline', () {
      expect(
        HarmonyLayout.dashY(baselineY: 50, space: 10),
        50 - HarmonyLayout.dashHeightSp * 10,
      );
    });
  });
}
