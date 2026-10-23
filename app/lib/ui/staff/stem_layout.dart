import 'dart:math' as math;

import 'staff_note.dart';

/// Implements Gould and MuseScore stem layout rules (`stemlayout.cpp`):
/// - Middle-line rule: single notes on or above the staff middle line (B4 on
///   treble, D3 on bass) have stems pointing DOWN. Notes below have stems pointing UP.
/// - Chord auto direction: votes based on the note farthest from the middle line.
/// - Ledger line elongation: stems on ledger lines extend to reach at least
///   the middle line of the staff.
abstract final class StemLayout {
  /// Diatonic step of middle staff line (Line 3).
  /// Treble: B4 (MIDI 71) -> diatonic step diatonicStep(71).
  /// Bass: D3 (MIDI 50) -> diatonicStep(50).
  static int middleLineStep(bool onBass) =>
      onBass ? diatonicStep(50) : diatonicStep(71);

  /// Computes whether the stem should point DOWN for a single note or chord.
  ///
  /// Respects [explicitStemDown] if provided. Otherwise uses MuseScore's
  /// auto-stem direction algorithm:
  /// - Single note: `step >= middleLineStep` -> DOWN (true), else UP (false).
  /// - Chord: examines the extreme notes (highest and lowest). The note
  ///   farthest from the middle line dictates the direction. If equidistant,
  ///   defaults to DOWN (standard Gould rule).
  static bool computeStemDown({
    required int pitch,
    required bool onBass,
    bool? explicitStemDown,
    List<int>? chordPitches,
  }) {
    if (explicitStemDown != null) return explicitStemDown;

    final mid = middleLineStep(onBass);

    if (chordPitches != null && chordPitches.length > 1) {
      final steps = chordPitches.map(diatonicStep).toList()..sort();
      final lowestStep = steps.first;
      final highestStep = steps.last;

      final distAbove = highestStep - mid;
      final distBelow = mid - lowestStep;

      if (distAbove > distBelow) {
        return true; // Extreme note is above -> stem DOWN
      } else if (distBelow > distAbove) {
        return false; // Extreme note is below -> stem UP
      } else {
        return true; // Equidistant -> default DOWN
      }
    }

    final step = diatonicStep(pitch);
    return step >= mid;
  }

  /// Calculates the Y coordinate of the stem tip with ledger-line elongation.
  ///
  /// Standard stem length is `3.5 * space`.
  /// For notes on ledger lines (Gould p. 14 / MuseScore `calcDefaultStemLength`):
  /// - If stem points DOWN and note is above staff: stem tip reaches at least [middleLineY].
  /// - If stem points UP and note is below staff: stem tip reaches at least [middleLineY].
  static double calcStemTipY({
    required double noteY,
    required bool stemDown,
    required double space,
    required double middleLineY,
  }) {
    final standardLength = space * 3.5;
    if (stemDown) {
      final nominalTip = noteY + standardLength;
      // If note is above middle line, ensure stem tip reaches at least to the middle line.
      if (noteY < middleLineY && nominalTip < middleLineY) {
        return middleLineY;
      }
      return nominalTip;
    } else {
      final nominalTip = noteY - standardLength;
      // If note is below middle line, ensure stem tip reaches at least to the middle line.
      if (noteY > middleLineY && nominalTip > middleLineY) {
        return middleLineY;
      }
      return nominalTip;
    }
  }

  /// X coordinate of stem attachment.
  ///
  /// Stems pointing UP attach to the right side of the notehead.
  /// Stems pointing DOWN attach to the left side of the notehead.
  static double stemX({
    required double noteheadX,
    required bool stemDown,
    required double space,
  }) {
    final strokeWidth = math.max(1.2, space * 0.1);
    final headWidth = space * 1.18;
    return stemDown ? noteheadX : (noteheadX + headWidth - strokeWidth);
  }
}
