import 'dart:math' as math;

import 'package:easy_piano/ui/staff/staff_note.dart';

/// Ottava sign of a spanner: `8va` (alta, above the staff) or `8vb` (bassa,
/// below it). Only these two; `15ma` and `22ma` are out of scope.
enum OttavaKind {
  /// `8va`: written an octave below the sounding pitch.
  /// `dom/ottava.h:68` (`OTTAVA_8VA`, shift 12).
  alta(12),

  /// `8vb`: written an octave above the sounding pitch.
  /// `dom/ottava.h:69` (`OTTAVA_8VB`, shift -12).
  bassa(-12);

  const OttavaKind(this.shift);

  /// MuseScore `pitchShift()` in semitones (`dom/ottava.cpp:256-259`):
  /// sounding pitch = written pitch + shift (`dom/note.cpp:2674`).
  final int shift;
}

/// One ottava spanner on one hand, in beats (same timeline as [StaffNote.beat]).
/// Covers the notes with `startBeat <= beat < endBeat`.
class StaffOttava {
  const StaffOttava({
    required this.kind,
    required this.startBeat,
    required this.endBeat,
    this.leftHand = false,
  });

  final OttavaKind kind;
  final double startBeat;
  final double endBeat;

  /// True when the directive sits in a left-hand (`LH`) bar.
  final bool leftHand;

  /// True when a note at [beat] on the given hand is under this spanner.
  bool covers(double beat, {required bool leftHand}) =>
      leftHand == this.leftHand &&
      beat >= startBeat - OttavaLayout.beatEpsilon &&
      beat < endBeat - OttavaLayout.beatEpsilon;
}

/// Ottava geometry and pitch display. Pure functions, no painting.
///
/// Follows MuseScore `dom/ottava.cpp`, `dom/staff.cpp` (`updateOttava`,
/// `pitchOffset`), `rendering/score/tlayout.cpp` (`layoutTextLineBaseSegment`)
/// and `rendering/score/tdraw.cpp` (`drawTextLineBaseSegment`). Each constant
/// names its source. Values in staff spaces (sp) unless stated.
///
/// Style values come from
/// `references/MuseScore/src/engraving/data/styles/legacy-style-defaults-v450.mss`
/// and, where the .mss and the built-in defaults agree, from
/// `style/styledef.cpp` (cited as well).
abstract final class OttavaLayout {
  /// Tolerance when comparing beats (same value as `StaffPainter`).
  static const beatEpsilon = 1e-6;

  // --- Line -----------------------------------------------------------------

  /// `ottavaLineWidth` = 0.11 sp (`legacy-style-defaults-v450.mss:544`,
  /// `style/styledef.cpp:727`).
  static const lineWidthSp = 0.11;

  /// `ottavaDashLineLen` = 6 (`mss:546`, `styledef.cpp:729`). Qt-style dash
  /// units: multiplied by the line width (`tdraw.cpp:1593-1598`, the pattern
  /// is `lineLength / lineWidth`).
  static const dashLen = 6.0;

  /// `ottavaDashGapLen` = 6 (`mss:547`, `styledef.cpp:730`), same units.
  static const gapLen = 6.0;

  /// `ottavaHookAbove` = 1 sp (`mss:542`, `styledef.cpp:725`).
  /// `ottavaHookBelow` is -1 in the .mss, normalised to +1 on load for files
  /// older than 460 (`style/style.cpp:391-392`, inside the block that starts
  /// at `style.cpp:374`). The built-in default is also 1 sp (`styledef.cpp:726`).
  static const hookHeightSp = 1.0;

  /// Line offset from the top staff line for `8va`: `ottavaPosAbove` y = -2
  /// (`mss:540`, `styledef.cpp:723`), applied as the default position
  /// (`dom/ottava.cpp:450-452`).
  static const posAboveSp = -2.0;

  /// Line offset from the bottom staff line for `8vb`: `ottavaPosBelow` y = 2
  /// (`mss:541`, `styledef.cpp:724`), added to the staff height
  /// (`tlayout.cpp:5940-5941`, `5945`).
  static const posBelowSp = 2.0;

  /// Y of the ottava line, screen coordinates (y grows downwards).
  /// [staffTop] and [staffBottom] are the top and bottom staff lines of the
  /// staff the spanner belongs to.
  static double lineY({
    required OttavaKind kind,
    required double staffTop,
    required double staffBottom,
    required double space,
  }) => switch (kind) {
    OttavaKind.alta => staffTop + posAboveSp * space,
    OttavaKind.bassa => staffBottom + posBelowSp * space,
  };

  /// Y of the end of the hook at the right end of the line. The hook points
  /// towards the staff: down for `8va`, up for `8vb`.
  /// Sign rule: `(placeBelow ? -1 : 1) * endHookHeight` (`tlayout.cpp:6103`);
  /// the hook is then drawn from those points (`tdraw.cpp:1805-1935`).
  static double hookEndY({
    required OttavaKind kind,
    required double lineY,
    required double space,
  }) => lineY + _hookSign(kind) * hookHeightSp * space;

  static double _hookSign(OttavaKind kind) =>
      kind == OttavaKind.alta ? 1.0 : -1.0;

  /// Dash spans along a line of [length] px, starting at 0, for a line of
  /// staff-space [space] (px per sp). Same rule as MuseScore
  /// `distributedDashPattern` (`tdraw.cpp:1593-1598`):
  /// `numPairs = max(1, L / (dash + gap))` and
  /// `newGap = (L - dash * (numPairs + 1)) / numPairs`, all in line widths.
  /// The pattern starts and ends with a dash, so the spans cover the whole
  /// line. Local choice: when `newGap` is negative (line too short for the
  /// pattern) the line is returned solid, because MuseScore would pass a
  /// negative gap to Qt.
  static List<({double from, double to})> dashSpans({
    required double length,
    required double space,
  }) {
    final lw = lineWidthSp * space;
    if (length <= 0 || lw <= 0) return const [];
    final pen = length / lw;
    final pairs = math.max(1, (pen / (dashLen + gapLen)).floor());
    final gap = (pen - dashLen * (pairs + 1)) / pairs;
    if (gap < 0) return [(from: 0.0, to: length)];
    final step = dashLen + gap;
    return [
      for (var k = 0; k <= pairs; k++)
        (from: k * step * lw, to: (k * step + dashLen) * lw),
    ];
  }

  // --- Pitch display --------------------------------------------------------

  /// Pitch to draw on the staff for a note at [pitch] (sounding MIDI) under a
  /// spanner. The sounding pitch is unchanged: only the staff position moves,
  /// so the drawn pitch is `pitch - kind.shift` (`8va` draws an octave lower).
  /// Source: MuseScore draws the written pitch and sounds `written + shift`
  /// (`dom/note.cpp:2653-2674`, `ppitch`); the spanner covers its tick range
  /// (`dom/staff.cpp:1278-1299`).
  static int displayPitch(
    int pitch, {
    required List<StaffOttava> ottavas,
    required double beat,
    required bool leftHand,
  }) {
    for (final o in ottavas) {
      if (o.covers(beat, leftHand: leftHand)) return pitch - o.kind.shift;
    }
    return pitch;
  }

  /// [notes] with pitches moved to their displayed positions. Rests and
  /// spacers keep their pitch. Returns [notes] itself when [ottavas] is empty.
  /// The result has the same length and order, so note indices still match.
  static List<StaffNote> displayNotes(
    List<StaffNote> notes,
    List<StaffOttava> ottavas,
  ) {
    if (ottavas.isEmpty) return notes;
    return [
      for (final n in notes)
        if (n.isRest || n.isSpacer)
          n
        else
          StaffNote(
            displayPitch(
              n.pitch,
              ottavas: ottavas,
              beat: n.beat,
              leftHand: n.leftHand,
            ),
            n.beat,
            n.beats,
            leftHand: n.leftHand,
            voice: n.voice,
            stemDown: n.stemDown,
            twoStems: n.twoStems,
            isRest: n.isRest,
            isSpacer: n.isSpacer,
            finger: n.finger,
            tie: n.tie,
            articulation: n.articulation,
            accidental: n.accidental,
            tuplet: n.tuplet,
          ),
    ];
  }
}
