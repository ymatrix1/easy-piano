import 'package:easy_piano/ui/staff/harmony_layout.dart';
import 'package:flutter_test/flutter_test.dart';

// Hand-computed values. Sources are in harmony_layout.dart (styledef.cpp line
// numbers) and in docs/specs/sheet-engraving.md. Space = 10 in the geometry
// tests, so 1 sp = 10 px.

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
    test('root size is 10 pt at a 1.75 mm spatium: 2.016 sp', () {
      // styledef.cpp:433 (10 pt), styledef.cpp:804 (1.75 mm).
      expect(HarmonyLayout.chordSizeSp, closeTo(10 * 25.4 / 72 / 1.75, 1e-12));
      expect(HarmonyLayout.chordSizeSp, closeTo(2.016, 0.001));
    });

    test('extension is inline at full size (no superscript)', () {
      // chordExtensionMag 1.0 and chordExtensionAdjust 0.0 (styledef.cpp:551-552).
      final runs = HarmonyLayout.chordRuns(ChordSymbol.parse('Am7')!);
      expect(runs.map((r) => r.text), ['A', 'm7']);
      expect(runs[1].scale, 1.0);
      expect(runs[1].riseSp, 0.0);
    });

    test('slash lowered 1/5 sp and bass lowered 2/5 sp at full size', () {
      // chords_legacy.xml:411 renderBase: m:-0.2:1 / m:0.2:1 :n, converted
      // from 1/5 sp units (compatutils.cpp:594-606). chordBassNoteScale 1.0.
      final runs = HarmonyLayout.chordRuns(ChordSymbol.parse('G7/B')!);
      expect(runs.map((r) => r.text), ['G', '7', '/', 'B']);
      expect(runs[2].riseSp, closeTo(-0.2, 1e-12));
      expect(runs[2].dxSp, closeTo(-0.04, 1e-12));
      expect(runs[3].scale, 1.0);
      expect(runs[3].riseSp, closeTo(-0.4, 1e-12));
      expect(runs[3].dxSp, 0.0);
    });

    test('a plain chord is one run', () {
      final runs = HarmonyLayout.chordRuns(ChordSymbol.parse('C')!);
      expect(runs.map((r) => r.text), ['C']);
    });

    test('default baseline is 2.5 sp above the top staff line', () {
      // chordSymbolAPosAbove y -2.5 (styledef.cpp:420). Space 10: 100 - 25.
      expect(HarmonyLayout.chordBaselineY(staffTopY: 100, space: 10), 75);
    });

    test('notes higher than the default baseline lift it, keeping 0.5 sp', () {
      // minHarmonyDistance 0.5 sp (styledef.cpp:407). Notehead top 70:
      // 70 - 5 = 65, which is above 75.
      expect(
        HarmonyLayout.chordBaselineY(staffTopY: 100, noteTopY: 70, space: 10),
        65,
      );
      // A notehead lower than the default baseline does not move it.
      expect(
        HarmonyLayout.chordBaselineY(staffTopY: 100, noteTopY: 120, space: 10),
        75,
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
    test('lyric font is 10 pt: 2.016 sp', () {
      // lyricsOddFontSize 10 (styledef.cpp:141), spatium 1.75 mm.
      expect(HarmonyLayout.lyricSizeSp, closeTo(2.016, 0.001));
    });

    test('a lyric is centred on its notehead centre', () {
      expect(HarmonyLayout.lyricLeft(centreX: 100, width: 40), 80);
    });

    test('the baseline sits 3 sp below the staff (lyricsPosBelow)', () {
      // Space 10, staff bottom 200, ascent 12. Nominal 200 + 3 * 10 = 230.
      // Floor 200 + 1 * 10 + 12 = 222. Max 230.
      expect(
        HarmonyLayout.lyricBaselineY(staffBottomY: 200, ascent: 12, space: 10),
        230,
      );
    });

    test('notes reaching the row push the baseline down', () {
      // Ink at 205: floor 205 + 10 + 12 = 227, under 230: no change.
      expect(
        HarmonyLayout.lyricBaselineY(
          staffBottomY: 200,
          lowestInkY: 205,
          ascent: 12,
          space: 10,
        ),
        230,
      );
      // A stem reaching 215: floor 215 + 10 + 12 = 237.
      expect(
        HarmonyLayout.lyricBaselineY(
          staffBottomY: 200,
          lowestInkY: 215,
          ascent: 12,
          space: 10,
        ),
        237,
      );
    });

    test('a tall ascent keeps the text 1 sp below the staff', () {
      // Ascent 25: floor 200 + 10 + 25 = 235, so the baseline moves from 230
      // to 235 and the text top sits at 210 (1 sp below the staff).
      expect(
        HarmonyLayout.lyricBaselineY(staffBottomY: 200, ascent: 25, space: 10),
        235,
      );
    });

    test('a hyphen is centred between the two syllables, 0.6 sp long', () {
      // Gap 30 minus 2 pads of 0.5 leaves 29. Hyphen is min(29, 6) = 6 long,
      // centred at (100.5 + 129.5) / 2 = 115 (lyricslayout.cpp:321-342).
      final segs = HarmonyLayout.hyphenSegments(
        prevRight: 100,
        nextLeft: 130,
        space: 10,
      );
      expect(segs, hasLength(1));
      expect(segs[0].x1 - segs[0].x0, closeTo(6, 1e-9));
      expect((segs[0].x0 + segs[0].x1) / 2, closeTo(115, 1e-9));
    });

    test('a short gap is still joined: widened to 0.4 sp, drawn', () {
      // Gap 2 (from 100.5 to 102.5). Forced to 4, centred at 101.5, so from
      // 99.5 to 103.5 (lyricsDashForce, lyricslayout.cpp:329-340).
      final segs = HarmonyLayout.hyphenSegments(
        prevRight: 100,
        nextLeft: 103,
        space: 10,
      );
      expect(segs, hasLength(1));
      expect(segs[0].x0, closeTo(101.5 - 2, 1e-9));
      expect(segs[0].x1, closeTo(101.5 + 2, 1e-9));
    });

    test('a gap over 16 sp gets one hyphen per 16 sp', () {
      // 399 long: ceil(399 / 160) = 3 hyphens, step 133, centres at 67, 200, 333
      // (lyricslayout.cpp:317-323, 346-360).
      final segs = HarmonyLayout.hyphenSegments(
        prevRight: 0,
        nextLeft: 400,
        space: 10,
      );
      expect(segs, hasLength(3));
      expect((segs[0].x0 + segs[0].x1) / 2, closeTo(67, 1e-9));
      expect((segs[1].x0 + segs[1].x1) / 2, closeTo(200, 1e-9));
      expect((segs[2].x0 + segs[2].x1) / 2, closeTo(333, 1e-9));
    });

    test('a melisma runs from 0.2 sp after the syllable to the note head', () {
      // lyricsMelismaPad 0.2 sp (styledef.cpp:123) and head right edge.
      final seg = HarmonyLayout.melismaSegment(
        textRight: 100,
        headRight: 140,
        space: 10,
      );
      expect(seg, isNotNull);
      expect(seg!.x0, closeTo(102, 1e-9));
      expect(seg.x1, closeTo(140, 1e-9));
    });

    test('a melisma shorter than 1 sp is not drawn', () {
      // lyricsMelismaMinLength 1 sp, not forced (styledef.cpp:129-130).
      expect(
        HarmonyLayout.melismaSegment(textRight: 100, headRight: 105, space: 10),
        isNull,
      );
    });

    test('hyphens and melisma lines sit 0.5 x-height above the baseline', () {
      // lyricsDashYposRatio 0.5 (styledef.cpp:126); x-height 0.5 em (local).
      expect(
        HarmonyLayout.dashY(baselineY: 50, space: 10),
        closeTo(50 - 0.5 * 0.5 * 2.016 * 10, 0.01),
      );
    });
  });
}
