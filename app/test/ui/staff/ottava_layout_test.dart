import 'package:easy_piano/ui/staff/ottava_layout.dart';
import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('style constants (legacy-style-defaults-v450.mss)', () {
    test('line width, dash pattern, hook height and offsets', () {
      expect(OttavaLayout.lineWidthSp, 0.11);
      expect(OttavaLayout.dashLen, 6);
      expect(OttavaLayout.gapLen, 6);
      expect(OttavaLayout.hookHeightSp, 1);
      expect(OttavaLayout.posAboveSp, -2);
      expect(OttavaLayout.posBelowSp, 2);
    });

    test('shifts match MuseScore ottavaDefault (8va +12, 8vb -12)', () {
      expect(OttavaKind.alta.shift, 12);
      expect(OttavaKind.bassa.shift, -12);
    });
  });

  group('displayPitch', () {
    const va = StaffOttava(kind: OttavaKind.alta, startBeat: 2, endBeat: 4);

    test('8va draws the note an octave lower inside its span', () {
      expect(
        OttavaLayout.displayPitch(
          84,
          ottavas: const [va],
          beat: 2,
          leftHand: false,
        ),
        72,
      );
      expect(
        OttavaLayout.displayPitch(
          84,
          ottavas: const [va],
          beat: 3.5,
          leftHand: false,
        ),
        72,
      );
    });

    test('the end beat is exclusive; before the start nothing moves', () {
      expect(
        OttavaLayout.displayPitch(
          84,
          ottavas: const [va],
          beat: 1.5,
          leftHand: false,
        ),
        84,
      );
      expect(
        OttavaLayout.displayPitch(
          84,
          ottavas: const [va],
          beat: 4,
          leftHand: false,
        ),
        84,
      );
    });

    test('a spanner on one hand does not move the other hand', () {
      expect(
        OttavaLayout.displayPitch(
          84,
          ottavas: const [va],
          beat: 2.5,
          leftHand: true,
        ),
        84,
      );
    });

    test('8vb draws the note an octave higher', () {
      const vb = StaffOttava(
        kind: OttavaKind.bassa,
        startBeat: 0,
        endBeat: 4,
        leftHand: true,
      );
      expect(
        OttavaLayout.displayPitch(
          36,
          ottavas: const [vb],
          beat: 1,
          leftHand: true,
        ),
        48,
      );
    });

    test('no spanner: pitch unchanged', () {
      expect(
        OttavaLayout.displayPitch(
          60,
          ottavas: const [],
          beat: 0,
          leftHand: false,
        ),
        60,
      );
    });
  });

  group('displayNotes', () {
    test('returns the same list when there are no ottavas', () {
      final notes = [const StaffNote(60, 0, 1)];
      expect(OttavaLayout.displayNotes(notes, const []), same(notes));
    });

    test('moves pitches only; keeps order, timing and other fields', () {
      const n = StaffNote(
        84,
        1,
        0.5,
        leftHand: false,
        voice: 2,
        stemDown: true,
        twoStems: true,
        finger: 3,
        tie: true,
        articulation: 'staccato',
        accidental: 'sharp',
        tuplet: 3,
      );
      const rest = StaffNote(0, 2, 1, isRest: true);
      const va = StaffOttava(kind: OttavaKind.alta, startBeat: 0, endBeat: 3);
      final out = OttavaLayout.displayNotes([n, rest], const [va]);

      expect(out, hasLength(2));
      final d = out[0];
      expect(d.pitch, 72);
      expect(d.beat, 1);
      expect(d.beats, 0.5);
      expect(d.leftHand, false);
      expect(d.voice, 2);
      expect(d.stemDown, true);
      expect(d.twoStems, true);
      expect(d.finger, 3);
      expect(d.tie, true);
      expect(d.articulation, 'staccato');
      expect(d.accidental, 'sharp');
      expect(d.tuplet, 3);
      expect(out[1].pitch, 0, reason: 'a rest keeps its pitch');
      expect(out[1].isRest, true);
    });

    test('does not mutate the input', () {
      final notes = [const StaffNote(84, 0, 1)];
      const va = StaffOttava(kind: OttavaKind.alta, startBeat: 0, endBeat: 1);
      OttavaLayout.displayNotes(notes, const [va]);
      expect(notes.single.pitch, 84);
    });
  });

  group('vertical placement (space = 10 px)', () {
    test('8va line 2 sp above the staff top; hook points down 1 sp', () {
      const space = 10.0;
      const top = 100.0;
      const bottom = 140.0;
      final y = OttavaLayout.lineY(
        kind: OttavaKind.alta,
        staffTop: top,
        staffBottom: bottom,
        space: space,
      );
      expect(y, 80);
      expect(
        OttavaLayout.hookEndY(kind: OttavaKind.alta, lineY: y, space: space),
        90,
      );
    });

    test('8vb line 2 sp below the staff bottom; hook points up 1 sp', () {
      const space = 10.0;
      const top = 100.0;
      const bottom = 140.0;
      final y = OttavaLayout.lineY(
        kind: OttavaKind.bassa,
        staffTop: top,
        staffBottom: bottom,
        space: space,
      );
      expect(y, 160);
      expect(
        OttavaLayout.hookEndY(kind: OttavaKind.bassa, lineY: y, space: space),
        150,
      );
    });
  });

  group('dashSpans', () {
    test('dashes and gaps are equal and cover the whole line', () {
      // space 10 -> line width 1.1 px. 200 px = 181.8 pen widths:
      // 15 pairs, gap (181.8 - 6 * 16) / 15 = 5.72 pen widths.
      const length = 200.0;
      final spans = OttavaLayout.dashSpans(length: length, space: 10);
      expect(spans, hasLength(16));
      expect(spans.first.from, 0);
      expect(spans.last.to, closeTo(length, 1e-9));
      for (final s in spans) {
        expect(s.to - s.from, closeTo(6 * 1.1, 1e-9));
      }
      for (var k = 1; k < spans.length; k++) {
        final gap = spans[k].from - spans[k - 1].to;
        expect(gap, closeTo(5.7212 * 1.1, 1e-3));
      }
    });

    test('a line too short for the pattern is drawn solid (local choice)', () {
      final spans = OttavaLayout.dashSpans(length: 5, space: 10);
      expect(spans, hasLength(1));
      expect(spans.single.from, 0);
      expect(spans.single.to, 5);
    });

    test('no length, no spans', () {
      expect(OttavaLayout.dashSpans(length: 0, space: 10), isEmpty);
    });
  });
}
