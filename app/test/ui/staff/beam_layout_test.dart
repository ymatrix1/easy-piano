import 'package:flutter_test/flutter_test.dart';
import 'package:easy_piano/ui/staff/beam_layout.dart';
import 'package:easy_piano/ui/staff/staff_note.dart';

void main() {
  group('BeamLayout (MuseScore beamlayout.cpp style)', () {
    test('groups consecutive sixteenth notes within the same beat', () {
      final notes = [
        const StaffNote(60, 0.0, 0.25), // C4 16th
        const StaffNote(62, 0.25, 0.25), // D4 16th
        const StaffNote(64, 0.5, 0.25), // E4 16th
        const StaffNote(65, 0.75, 0.25), // F4 16th
        // Next beat:
        const StaffNote(67, 1.0, 0.25),
        const StaffNote(65, 1.25, 0.25),
      ];

      final groups = BeamLayout.computeBeamGroups(
        notes: notes,
        first: 0,
        lastBeat: 2.0,
        onBass: (_) => false,
        noteY: (pitch, _) => 100.0 - (pitch - 60) * 5.0,
        noteXs: {for (var i = 0; i < notes.length; i++) i: i * 20.0},
        space: 10.0,
        beatsPerBar: 4.0,
      );

      expect(groups.length, equals(2));
      // First beat group has 4 sixteenth notes
      expect(groups[0].indices, equals([0, 1, 2, 3]));
      // Second beat group has 2 sixteenth notes
      expect(groups[1].indices, equals([4, 5]));
    });

    test('isolated eighth notes followed by a rest are not beamed', () {
      final notes = [
        const StaffNote(60, 0.0, 0.5), // isolated 8th note
        const StaffNote(60, 0.5, 0.5, isRest: true), // rest
        const StaffNote(64, 1.0, 1.0), // quarter note
      ];

      final groups = BeamLayout.computeBeamGroups(
        notes: notes,
        first: 0,
        lastBeat: 2.0,
        onBass: (_) => false,
        noteY: (pitch, _) => 100.0,
        noteXs: {for (var i = 0; i < notes.length; i++) i: i * 30.0},
        space: 10.0,
        beatsPerBar: 4.0,
      );

      // Isolated note has no companions to form a beam group
      expect(groups, isEmpty);
    });

    test('beam slope is clamped according to MuseScore max slope', () {
      final notes = [
        const StaffNote(60, 0.0, 0.25), // Low pitch
        const StaffNote(84, 0.25, 0.25), // High pitch (large vertical delta)
      ];

      const space = 10.0;
      final groups = BeamLayout.computeBeamGroups(
        notes: notes,
        first: 0,
        lastBeat: 1.0,
        onBass: (_) => false,
        noteY: (pitch, _) => (pitch == 60 ? 120.0 : 40.0),
        noteXs: {0: 10.0, 1: 50.0},
        space: space,
        beatsPerBar: 4.0,
      );

      expect(groups.length, equals(1));
      final g = groups.first;
      final dx = g.stemXs[1]! - g.stemXs[0]!;
      final maxSlope = (space * 0.8) / dx;
      expect(g.slope.abs(), lessThanOrEqualTo(maxSlope + 1e-6));
    });

    test('4/4 meter beams four consecutive eighth notes in half-measure (beats 0-2)', () {
      final notes = [
        const StaffNote(60, 0.0, 0.5),
        const StaffNote(62, 0.5, 0.5),
        const StaffNote(64, 1.0, 0.5),
        const StaffNote(65, 1.5, 0.5),
        // Beat 2-4:
        const StaffNote(67, 2.0, 0.5),
        const StaffNote(69, 2.5, 0.5),
        const StaffNote(71, 3.0, 0.5),
        const StaffNote(72, 3.5, 0.5),
      ];

      final groups = BeamLayout.computeBeamGroups(
        notes: notes,
        first: 0,
        lastBeat: 4.0,
        onBass: (_) => false,
        noteY: (pitch, _) => 100.0,
        noteXs: {for (var i = 0; i < notes.length; i++) i: i * 20.0},
        space: 10.0,
        beatsPerBar: 4.0,
      );

      // Must be split into two 4-note groups at beat 2.0 (half-measure boundary)
      expect(groups.length, equals(2));
      expect(groups[0].indices, equals([0, 1, 2, 3]));
      expect(groups[1].indices, equals([4, 5, 6, 7]));
    });

    test(
      'groups consecutive chords and includes all chord indices in allIndices',
      () {
        // Dyads on beat 0.0 and 0.5 (like Rondo alla Turca E5G5:8 E5G5:8)
        final notes = [
          const StaffNote(76, 0.0, 0.5), // E5 (idx 0)
          const StaffNote(79, 0.0, 0.5), // G5 (idx 1)
          const StaffNote(76, 0.5, 0.5), // E5 (idx 2)
          const StaffNote(79, 0.5, 0.5), // G5 (idx 3)
        ];

        final groups = BeamLayout.computeBeamGroups(
          notes: notes,
          first: 0,
          lastBeat: 1.0,
          onBass: (_) => false,
          noteY: (pitch, _) => 100.0 - (pitch - 60) * 5.0,
          noteXs: {0: 10.0, 1: 10.0, 2: 40.0, 3: 40.0},
          space: 10.0,
          beatsPerBar: 4.0,
        );

        expect(groups.length, equals(1));
        // Primary indices (one per beat)
        expect(groups[0].indices, equals([0, 2]));
        // All note indices across all chords in the group are tracked
        expect(groups[0].allIndices, equals([0, 1, 2, 3]));
      },
    );

    test(
      'computes independent beam groups for treble and bass simultaneously',
      () {
        // 4 eighth notes in treble and 4 eighth notes in bass playing at the same beats
        final notes = [
          // Beat 0.0
          const StaffNote(60, 0.0, 0.5, leftHand: false), // idx 0 RH C4
          const StaffNote(48, 0.0, 0.5, leftHand: true), // idx 1 LH C3
          // Beat 0.5
          const StaffNote(62, 0.5, 0.5, leftHand: false), // idx 2 RH D4
          const StaffNote(50, 0.5, 0.5, leftHand: true), // idx 3 LH D3
          // Beat 1.0
          const StaffNote(64, 1.0, 0.5, leftHand: false), // idx 4 RH E4
          const StaffNote(52, 1.0, 0.5, leftHand: true), // idx 5 LH E3
          // Beat 1.5
          const StaffNote(65, 1.5, 0.5, leftHand: false), // idx 6 RH F4
          const StaffNote(53, 1.5, 0.5, leftHand: true), // idx 7 LH F3
        ];

        final groups = BeamLayout.computeBeamGroups(
          notes: notes,
          first: 0,
          lastBeat: 2.0,
          onBass: (n) => n.leftHand,
          noteY: (pitch, onBass) => onBass ? 200.0 : 100.0,
          noteXs: {
            for (var i = 0; i < notes.length; i++) i: (notes[i].beat * 40.0),
          },
          space: 10.0,
          beatsPerBar: 4.0,
        );

        // Both treble and bass must have their own independent beam group!
        expect(groups.length, equals(2));
        final trebleGroup = groups.firstWhere((g) => !g.stemDown);
        final bassGroup = groups.firstWhere((g) => g.stemDown);

        expect(trebleGroup.allIndices, equals([0, 2, 4, 6]));
        expect(bassGroup.allIndices, equals([1, 3, 5, 7]));
      },
    );

    test('does not beam single bass note to offbeat accompaniment chord (Gould p. 306)', () {
      // Mozart Rondo alla Turca bar 4: A3:8 (single bass note) then C4E4:8 (chord)
      final notes = [
        const StaffNote(57, 0.0, 0.5, leftHand: true), // idx 0: A3 single note
        const StaffNote(60, 0.5, 0.5, leftHand: true), // idx 1: C4 in chord
        const StaffNote(64, 0.5, 0.5, leftHand: true), // idx 2: E4 in chord
      ];

      final groups = BeamLayout.computeBeamGroups(
        notes: notes,
        first: 0,
        lastBeat: 1.0,
        onBass: (_) => true,
        noteY: (pitch, _) => 200.0 - (pitch - 50) * 5.0,
        noteXs: {0: 10.0, 1: 30.0, 2: 30.0},
        space: 10.0,
        beatsPerBar: 4.0,
      );

      // Accompaniment single bass note must not be beamed to the offbeat chord!
      expect(groups, isEmpty);
    });
  });
}
