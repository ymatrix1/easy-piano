import 'package:easy_piano/ui/staff/chord_layout.dart';
import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChordLayout second collision avoidance (MuseScore chordlayout.cpp)', () {
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
      expect(offsets[1], closeTo(headWidth, 0.01)); // upper note shifted right
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
      expect(offsets[0], closeTo(-headWidth, 0.01)); // lower note shifted left
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

    test('computeAccidentalOffsets staggers accidentals when vertically closer than 2.2 spaces (MuseScore accidentalslayout.cpp)', () {
      // Chord with D#5 (75) and F#5 (78): a third apart, vertical distance is only 1.0 space!
      final notes = [
        const StaffNote(75, 0.0, 1.0, accidental: 'sharp'),
        const StaffNote(78, 0.0, 1.0, accidental: 'sharp'),
      ];
      final accOffsets = ChordLayout.computeAccidentalOffsets(
        notes: notes,
        chordIndices: const [0, 1],
        noteAccidentals: const {0: 'sharp', 1: 'sharp'},
        noteY: (pitch, onBass) => pitch == 75 ? 50.0 : 40.0,
        onBass: false,
        space: space,
      );

      // Higher note (78) stays in column 0 (0.0), lower note (75) is staggered to column 1 (-col * space * 1.15)
      expect(accOffsets[1], equals(0.0));
      expect(accOffsets[0], closeTo(-space * 1.15, 0.01));
    });

    test('leftmostNoteheadOffset returns minimum head offset across chord', () {
      final chordHeadOffsets = {0: -headWidth, 1: 0.0, 2: headWidth};
      final minOffset = ChordLayout.leftmostNoteheadOffset(
        chordIndices: const [0, 1, 2],
        chordHeadOffsets: chordHeadOffsets,
      );
      expect(minOffset, closeTo(-headWidth, 0.01));
    });

    test('computeDotOffsets aligns dots horizontally to rightmost note and resolves vertical space conflict (MuseScore chordlayout.cpp)', () {
      // Dotted chord with two adjacent notes: C4 (60, line) and D4 (62, space)
      final notes = [
        const StaffNote(60, 0.0, 1.5),
        const StaffNote(62, 0.0, 1.5),
      ];
      final dotOffsets = ChordLayout.computeDotOffsets(
        notes: notes,
        chordIndices: const [0, 1],
        chordHeadOffsets: const {0: 0.0, 1: 0.0},
        space: space,
      );

      expect(dotOffsets.length, equals(2));
      // Both dots align to the same horizontal X coordinate
      final (dot0X, _) = dotOffsets[0]!;
      final (dot1X, _) = dotOffsets[1]!;
      expect(dot0X, closeTo(dot1X, 0.01));
    });
  });
}
