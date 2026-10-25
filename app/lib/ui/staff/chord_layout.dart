import 'dart:math' as math;

import 'staff_note.dart';

/// Implements chord engraving layout following MuseScore Studio
/// (`chordlayout.cpp`, `accidentalslayout.cpp`, `horizontalspacing.cpp`) and Gould rules:
/// - Notehead displacement on seconds (intervals of a 2nd)
/// - Accidental vertical staggering and leftmost chord alignment
/// - Augmentation dot conflict resolution and alignment
/// - Beat clearance calculation (`lll` and `rrr`) for collision-free horizontal spacing
abstract final class ChordLayout {
  /// Whether a duration in beats has an augmentation dot.
  static bool isDotted(double beats) =>
      (beats - 1.5).abs() < 1e-4 ||
      (beats - 3.0).abs() < 1e-4 ||
      (beats - 0.75).abs() < 1e-4 ||
      (beats - 0.375).abs() < 1e-4;

  /// Computes horizontal offset (in pixels) for each note in a chord at the same
  /// beat and staff (MuseScore `chordlayout.cpp` lines 131-155).
  ///
  /// - When stem is UP: lower note sits on normal (left) side, higher note is shifted right.
  /// - When stem is DOWN: higher note sits on normal (right) side, lower note is shifted left.
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

  /// Finds the leftmost notehead X offset in a chord group.
  ///
  /// When notes in a chord are displaced (e.g. interval of a second),
  /// accidentals must sit to the left of the leftmost notehead.
  static double leftmostNoteheadOffset({
    required List<int> chordIndices,
    required Map<int, double> chordHeadOffsets,
  }) {
    var minOffset = 0.0;
    for (final idx in chordIndices) {
      final hx = chordHeadOffsets[idx] ?? 0.0;
      if (hx < minOffset) minOffset = hx;
    }
    return minOffset;
  }

  /// Computes accidental staggering offsets for notes in a chord
  /// following MuseScore `accidentalslayout.cpp` lines 291-308.
  ///
  /// When multiple accidentals in the same chord are closer vertically than
  /// 2.2 spaces, they are staggered into multiple horizontal columns to avoid collision.
  static Map<int, double> computeAccidentalOffsets({
    required List<StaffNote> notes,
    required List<int> chordIndices,
    required Map<int, dynamic> noteAccidentals,
    required double Function(int pitch, bool onBass) noteY,
    required bool onBass,
    required double space,
  }) {
    final offsets = <int, double>{};
    final accNotes = <int>[];
    for (final idx in chordIndices) {
      if (noteAccidentals.containsKey(idx)) accNotes.add(idx);
    }
    if (accNotes.length <= 1) {
      for (final idx in accNotes) {
        offsets[idx] = 0.0;
      }
      return offsets;
    }

    accNotes.sort((a, b) => notes[a].pitch.compareTo(notes[b].pitch));
    var col = 0;
    double? lastY;
    for (var k = accNotes.length - 1; k >= 0; k--) {
      final idx = accNotes[k];
      final ny = noteY(notes[idx].pitch, onBass);
      if (lastY != null && (lastY - ny).abs() < space * 2.2) {
        col++;
      }
      offsets[idx] = -col * space * 1.15;
      lastY = ny;
    }
    return offsets;
  }

  /// Computes augmentation dot alignment and conflict resolution
  /// following MuseScore `chordlayout.cpp` (`getNoteListForDots` / `placeDots`).
  ///
  /// Dots align horizontally to the right of the rightmost notehead in the chord.
  /// Vertical positions avoid line clashes: if a note sits on a line, its dot
  /// sits in the space above; if that space is already occupied by another dot,
  /// it sits in the space below.
  static Map<int, (double dx, double dy)> computeDotOffsets({
    required List<StaffNote> notes,
    required List<int> chordIndices,
    required Map<int, double> chordHeadOffsets,
    required double space,
  }) {
    final dotOffsets = <int, (double, double)>{};
    final dottedNotes = chordIndices
        .where((idx) => isDotted(notes[idx].beats))
        .toList();
    if (dottedNotes.isEmpty) return dotOffsets;

    var maxHeadX = -1e9;
    for (final idx in chordIndices) {
      final hx = chordHeadOffsets[idx] ?? 0.0;
      final hw = (notes[idx].beats >= 4 ? 1.5 : 1.3) * space;
      if (hx + hw > maxHeadX) maxHeadX = hx + hw;
    }
    final dotBaseX = maxHeadX + space * 0.45;
    dottedNotes.sort((a, b) => notes[b].pitch.compareTo(notes[a].pitch));
    final occupiedSpaces = <int>{};
    final half = space / 2;

    for (final idx in dottedNotes) {
      final st = diatonicStep(notes[idx].pitch);
      int dotSpace;
      if (st.isOdd) {
        dotSpace = st;
      } else {
        if (!occupiedSpaces.contains(st + 1)) {
          dotSpace = st + 1;
        } else {
          dotSpace = st - 1;
        }
      }
      occupiedSpaces.add(dotSpace);
      final dy = -(dotSpace - st) * half;
      final headOffset = chordHeadOffsets[idx] ?? 0.0;
      dotOffsets[idx] = (dotBaseX - headOffset, dy);
    }
    return dotOffsets;
  }

  /// Computes required left clearance (`lll`) and right clearance (`rrr`) for a
  /// beat's cluster of notes (MuseScore `chordlayout.cpp` lines 131-155).
  static ({double leftClearance, double rightClearance}) computeBeatClearances({
    required List<StaffNote> notes,
    required List<int> noteIndices,
    required Map<int, double> chordHeadOffsets,
    required Map<int, double> chordAccidentalOffsets,
    required Map<int, (double, double)> chordDotOffsets,
    required Map<int, dynamic> noteAccidentals,
    required Map<(int, bool), List<int>> chordGroups,
    required double space,
  }) {
    var maxL = 0.0;
    var maxR = 0.0;

    for (final idx in noteIndices) {
      final note = notes[idx];
      final hOffset = chordHeadOffsets[idx] ?? 0.0;
      final hw = note.isRest ? 1.0 : (note.beats >= 4 ? 1.5 : 1.3);
      final rightEdge = hOffset + hw * space;
      if (rightEdge > maxR) maxR = rightEdge;

      if (isDotted(note.beats)) {
        final dotInfo = chordDotOffsets[idx];
        final dotRight =
            (dotInfo != null ? dotInfo.$1 : (hw + 0.45) * space) + space * 0.4;
        if (dotRight > maxR) maxR = dotRight;
      }

      if (-hOffset > maxL) maxL = -hOffset;

      if (noteAccidentals.containsKey(idx)) {
        final beatInt = (note.beat * 1000).round();
        final grp = chordGroups[(beatInt, note.leftHand)];
        final lmHead = grp != null
            ? leftmostNoteheadOffset(
                chordIndices: grp,
                chordHeadOffsets: chordHeadOffsets,
              )
            : math.min(0.0, hOffset);
        final extra = chordAccidentalOffsets[idx] ?? 0.0;
        final accLeft = -(lmHead - space * 1.3 + extra);
        if (accLeft > maxL) maxL = accLeft;
      }
    }

    return (leftClearance: maxL, rightClearance: maxR);
  }
}
