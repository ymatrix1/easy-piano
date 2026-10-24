import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:easy_piano/ui/staff/tuplet_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TupletLayout (MuseScore tupletlayout.cpp style)', () {
    test('Identifies and groups 3 consecutive triplet notes', () {
      final notes = [
        const StaffNote(60, 0.0, 0.333, tuplet: 3),
        const StaffNote(62, 0.333, 0.333, tuplet: 3),
        const StaffNote(64, 0.666, 0.334, tuplet: 3),
        // Normal note:
        const StaffNote(65, 1.0, 1.0),
      ];

      final groups = TupletLayout.computeTupletGroups(
        notes: notes,
        first: 0,
        lastBeat: 2.0,
        noteXs: {0: 10.0, 1: 30.0, 2: 50.0, 3: 80.0},
        noteY: (pitch, _) => 100.0,
        onBass: (_) => false,
        beamedIndices: {0, 1, 2},
        space: 10.0,
      );

      expect(groups.length, equals(1));
      final g = groups.first;
      expect(g.number, equals(3));
      expect(g.indices, equals([0, 1, 2]));
      expect(g.hasBeam, isTrue);
    });

    test(
      'Unbeamed triplets have hasBeam = false (triggers bracket rendering)',
      () {
        final notes = [
          const StaffNote(60, 0.0, 0.666, tuplet: 3), // quarter note triplets
          const StaffNote(62, 0.666, 0.666, tuplet: 3),
          const StaffNote(64, 1.333, 0.666, tuplet: 3),
        ];

        final groups = TupletLayout.computeTupletGroups(
          notes: notes,
          first: 0,
          lastBeat: 2.0,
          noteXs: {0: 10.0, 1: 40.0, 2: 70.0},
          noteY: (pitch, _) => 100.0,
          onBass: (_) => false,
          beamedIndices: {}, // No beams
          space: 10.0,
        );

        expect(groups.length, equals(1));
        expect(groups.first.hasBeam, isFalse);
      },
    );
  });
}
