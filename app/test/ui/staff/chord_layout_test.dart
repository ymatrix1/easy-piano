import 'package:easy_piano/ui/staff/chord_layout.dart';
import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(
    'ChordLayout second collision avoidance (MuseScore chordlayout.cpp)',
    () {
      const space = 10.0;
      final headWidth = space * 1.18;

      test('Diatonic second with stem UP: lower note normal, upper note shifted right', () {
        final notes = [
          const StaffNote(60, 0.0, 1.0), // C4 (step -4)
          const StaffNote(62, 0.0, 1.0), // D4 (step -3) - interval of a 2nd
        ];

        final offsets = ChordLayout.computeNoteheadOffsets(
          notes: notes,
          chordIndices: const [0, 1],
          stemDown: false,
          space: space,
        );

        expect(offsets[0], 0.0); // lower note on left of stem
        expect(
          offsets[1],
          closeTo(headWidth, 0.01),
        ); // upper note shifted right
      });

      test('Diatonic second with stem DOWN: upper note normal, lower note shifted left', () {
        final notes = [
          const StaffNote(71, 0.0, 1.0), // B4 (step 3)
          const StaffNote(72, 0.0, 1.0), // C5 (step 4) - interval of a 2nd
        ];

        final offsets = ChordLayout.computeNoteheadOffsets(
          notes: notes,
          chordIndices: const [0, 1],
          stemDown: true,
          space: space,
        );

        expect(offsets[1], 0.0); // upper note on right of stem
        expect(
          offsets[0],
          closeTo(-headWidth, 0.01),
        ); // lower note shifted left
      });

      test(
        'Non-second interval (third, C4 and E4): both notes sit at offset 0',
        () {
          final notes = [
            const StaffNote(60, 0.0, 1.0), // C4
            const StaffNote(64, 0.0, 1.0), // E4 (third)
          ];

          final offsets = ChordLayout.computeNoteheadOffsets(
            notes: notes,
            chordIndices: const [0, 1],
            stemDown: false,
            space: space,
          );

          expect(offsets[0], 0.0);
          expect(offsets[1], 0.0);
        },
      );
    },
  );
}
