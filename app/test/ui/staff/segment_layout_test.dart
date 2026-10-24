import 'package:easy_piano/ui/staff/key_signature.dart';
import 'package:easy_piano/ui/staff/segment_layout.dart';
import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SegmentLayout (MuseScore parity)', () {
    const space = 10.0;
    const anchorX = 100.0;
    const nowBeat = 0.0;
    const ppb = 60.0;

    test(
      'RH and LH notes on the exact same beat share identical X coordinate',
      () {
        final notes = [
          const StaffNote(72, 1.0, 1.0, leftHand: false), // RH C5 on beat 1.0
          const StaffNote(48, 1.0, 1.0, leftHand: true), // LH C3 on beat 1.0
        ];

        final segments = SegmentLayout.buildSegments(
          notes: notes,
          anchorX: anchorX,
          nowBeat: nowBeat,
          pixelsPerBeat: ppb,
          space: space,
          beatsPerBar: 4.0,
          noteAccidentals: const {},
        );

        expect(segments.length, equals(1));
        expect(segments[0].noteIndices, equals([0, 1]));

        final xCache = SegmentLayout.computeNoteXs(segments);
        expect(xCache[0], equals(xCache[1]));
        expect(xCache[0], equals(anchorX + 1.0 * ppb));
      },
    );

    test(
      'accidental in one hand expands segment clearance for all voices on beat',
      () {
        final notes = [
          const StaffNote(60, 0.0, 0.5), // C4 at 0.0
          const StaffNote(61, 0.25, 0.5), // C#4 at 0.25
        ];

        final segments = SegmentLayout.buildSegments(
          notes: notes,
          anchorX: anchorX,
          nowBeat: nowBeat,
          pixelsPerBeat: 20.0, // tight ppb
          space: space,
          beatsPerBar: 4.0,
          noteAccidentals: const {1: AccidentalType.sharp},
        );

        expect(segments.length, equals(2));
        final xCache = SegmentLayout.computeNoteXs(segments);

        final nominalX1 = anchorX + 0.25 * 20.0;
        // segment 1 has accidental, so minGap and leftOffset push it right
        expect(xCache[1]!, greaterThan(nominalX1));
      },
    );

    test('barLineX places barline cleanly between adjacent segments', () {
      final notes = [
        const StaffNote(60, 3.5, 0.5), // beat 3.5
        const StaffNote(62, 4.0, 1.0), // beat 4.0
      ];

      final segments = SegmentLayout.buildSegments(
        notes: notes,
        anchorX: anchorX,
        nowBeat: nowBeat,
        pixelsPerBeat: ppb,
        space: space,
        beatsPerBar: 4.0,
        noteAccidentals: const {},
      );

      final bx = SegmentLayout.barLineX(
        barBeat: 4.0,
        nowBeat: nowBeat,
        anchorX: anchorX,
        pixelsPerBeat: ppb,
        space: space,
        segments: segments,
      );

      final seg0 = segments[0];
      final seg1 = segments[1];
      expect(bx, greaterThan(seg0.x + seg0.rightWidth * space));
      expect(bx, lessThan(seg1.x - seg1.leftOffset * space));
    });
  });
}
