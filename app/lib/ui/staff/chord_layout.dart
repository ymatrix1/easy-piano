import 'staff_note.dart';

/// Implements chord notehead displacement to prevent collisions on seconds
/// (intervals of a 2nd), following MuseScore `chordlayout.cpp` and Gould rules:
/// - When stem is UP: lower note sits on normal (left) side, higher note is
///   shifted right.
/// - When stem is DOWN: higher note sits on normal (right) side, lower note is
///   shifted left.
abstract final class ChordLayout {
  /// Computes horizontal offset (in pixels) for each note in a chord at the same
  /// beat and staff.
  ///
  /// Returns a map from note index to horizontal X offset.
  static Map<int, double> computeNoteheadOffsets({
    required List<StaffNote> notes,
    required List<int> chordIndices,
    required bool stemDown,
    required double space,
  }) {
    final offsets = <int, double>{};
    if (chordIndices.length <= 1) {
      for (final idx in chordIndices) {
        offsets[idx] = 0.0;
      }
      return offsets;
    }

    final headWidth = space * 1.18;

    // Sort indices by diatonic step ascending (lowest pitch to highest pitch)
    final sorted = List<int>.from(chordIndices)
      ..sort(
        (a, b) =>
            diatonicStep(notes[a].pitch)
                .compareTo(diatonicStep(notes[b].pitch)),
      );

    // Track assigned shifts: 0 = normal, 1 = right (+headWidth), -1 = left (-headWidth)
    final shifts = <int, int>{};
    for (final idx in sorted) {
      shifts[idx] = 0;
    }

    // Check adjacent pairs for intervals of a second (diatonic step difference == 1)
    for (var i = 0; i < sorted.length - 1; i++) {
      final lowerIdx = sorted[i];
      final upperIdx = sorted[i + 1];
      final stepLower = diatonicStep(notes[lowerIdx].pitch);
      final stepUpper = diatonicStep(notes[upperIdx].pitch);

      if (stepUpper - stepLower == 1) {
        // Interval of a second
        if (stemDown) {
          // In downward stem: upper note is normal (right), lower note is displaced LEFT
          if (shifts[upperIdx] == 0) {
            shifts[lowerIdx] = -1;
          } else {
            shifts[upperIdx] = 1;
          }
        } else {
          // In upward stem: lower note is normal (left), upper note is displaced RIGHT
          if (shifts[lowerIdx] == 0) {
            shifts[upperIdx] = 1;
          } else {
            shifts[lowerIdx] = -1;
          }
        }
      }
    }

    for (final idx in sorted) {
      final shift = shifts[idx] ?? 0;
      offsets[idx] = shift * headWidth;
    }

    return offsets;
  }
}
