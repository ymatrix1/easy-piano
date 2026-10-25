import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ornament over a chord: `{trill}`, `{mordent}` or `{turn}`.
enum OrnamentKind { trill, mordent, turn }

/// An ornament on the chord at [beat] in one hand.
class StaffOrnament {
  const StaffOrnament(this.beat, this.kind, {this.leftHand = false});

  /// Onset of the chord, same timeline as [StaffNote.beat].
  final double beat;
  final OrnamentKind kind;

  /// True when the directive sits in a left-hand (`LH`) bar.
  final bool leftHand;
}

/// An acciaccatura before the chord at [beat] (`{acc:"D5"}`).
///
/// The grace note takes no time: it is drawn just left of the chord that starts
/// at [beat], and the timeline does not move.
class StaffAcciaccatura {
  const StaffAcciaccatura({
    required this.beat,
    required this.pitch,
    this.accidental,
    this.leftHand = false,
  });

  /// Onset of the main chord the grace note leans on.
  final double beat;

  /// MIDI pitch of the grace note (60 = middle C).
  final int pitch;

  /// Written accidental: 'sharp', 'flat', 'natural', or null (none written).
  final String? accidental;
  final bool leftHand;
}

/// One SMuFL glyph with its bounding box, in staff spaces relative to the
/// baseline-left origin (SW = bottom-left, NE = top-right).
class OrnamentGlyph {
  const OrnamentGlyph(
    this.glyph, {
    required this.swX,
    required this.swY,
    required this.neX,
    required this.neY,
  });

  final String glyph;
  final double swX;
  final double swY;
  final double neX;
  final double neY;
}

/// Ornament and acciaccatura geometry. Pure functions, no painting state.
///
/// Follows MuseScore `rendering/score/tlayout.cpp` (`layoutOrnament`: the
/// ornament sits centred above the chord with a vertical margin of 0.35 sp)
/// and `rendering/score/chordlayout.cpp` (grace notes are scaled by
/// `graceNoteMag`, 0.6, and sit before the main chord, stem up).
///
/// Glyph codepoints are SMuFL names from `fonts/smufl/glyphnames.json`
/// (checked against the cmap of `assets/fonts/Leland.otf`). Bounding boxes
/// come from `fonts/leland/leland_metadata.json`.
abstract final class OrnamentLayout {
  /// `ornamentTrill` (U+E566): bbox x -0.048..1.532, y 0..1.532 sp.
  static const trill = OrnamentGlyph(
    '\uE566',
    swX: -0.048,
    swY: 0.0,
    neX: 1.532,
    neY: 1.532,
  );

  /// `ornamentMordent` (U+E56D): bbox x 0..1.892, y -0.308..1.264 sp.
  static const mordent = OrnamentGlyph(
    '\uE56D',
    swX: 0.0,
    swY: -0.308,
    neX: 1.892,
    neY: 1.264,
  );

  /// `ornamentTurn` (U+E567): bbox x 0..1.824, y 0..0.928 sp.
  static const turn = OrnamentGlyph(
    '\uE567',
    swX: 0.0,
    swY: 0.0,
    neX: 1.824,
    neY: 0.928,
  );

  /// `graceNoteSlashStemUp` (U+E564): bbox x 0..1.956, y 0..1.196 sp. The
  /// oblique slash through the stem of a stem-up grace note. (U+E560 is
  /// `graceNoteAcciaccaturaStemUp`, a whole acciaccatura, not the slash.)
  static const slash = OrnamentGlyph(
    '\uE564',
    swX: 0.0,
    swY: 0.0,
    neX: 1.956,
    neY: 1.196,
  );

  /// Ink width of a black notehead (`noteheadBlack`, bbox x 0..1.3 sp).
  static const headWidthSp = 1.3;

  /// Half the ink height of a black notehead (bbox y -0.532..0.528 sp).
  static const headHalfHeightSp = 0.5;

  /// Width of an accidental glyph at full size, in staff spaces.
  static const accidentalWidthSp = 1.0;

  /// Scale of grace notes against main notes (MuseScore `graceNoteMag`).
  static const graceScale = 0.6;

  /// Standard stem length, in staff spaces (MuseScore `stemLength`).
  static const stemLengthSp = 3.5;

  /// Gap between the right edge of the grace head and the chord it leans on.
  static const graceGapSp = 0.5;

  /// Gap between a grace accidental and its grace head.
  static const graceAccidentalGapSp = 0.2;

  /// Vertical margin between an ornament and the top of the chord
  /// (MuseScore `layoutOrnament`: `vertMargin` 0.35 sp).
  static const ornamentGapSp = 0.35;

  /// Gap between the trill glyph and the start of its wavy line.
  static const trillLineStartGapSp = 0.2;

  /// Gap between the wavy line and the next notehead.
  static const trillLineEndGapSp = 0.3;

  /// Shortest wavy line worth drawing, in staff spaces.
  static const minTrillLineSp = 1.0;

  /// Wave amplitude (peak to centre), wavelength and stroke width of the
  /// generated trill line, in staff spaces.
  static const waveAmplitudeSp = 0.12;
  static const waveLengthSp = 0.7;
  static const waveStrokeSp = 0.12;

  /// Glyph for an ornament kind.
  static OrnamentGlyph glyphFor(OrnamentKind kind) => switch (kind) {
    OrnamentKind.trill => trill,
    OrnamentKind.mordent => mordent,
    OrnamentKind.turn => turn,
  };

  /// Centre x of a notehead whose ink starts at [headLeftX].
  static double headCentreX(double headLeftX, double space) =>
      headLeftX + headWidthSp * space / 2;

  /// Top of the ink an ornament must clear: the top edge of the highest
  /// notehead ([headYs] are head centres, screen y grows downwards), or a
  /// stem tip that rises above it ([stemTipYs]).
  static double topInkY({
    required Iterable<double> headYs,
    required Iterable<double> stemTipYs,
    required double space,
  }) {
    var top = double.infinity;
    for (final y in headYs) {
      top = math.min(top, y - headHalfHeightSp * space);
    }
    for (final y in stemTipYs) {
      top = math.min(top, y);
    }
    return top;
  }

  /// Baseline-left origin of an ornament centred on [centreX], with its ink
  /// bottom [ornamentGapSp] above [topInkY].
  static Offset ornamentOrigin({
    required OrnamentKind kind,
    required double centreX,
    required double topInkY,
    required double space,
  }) {
    final g = glyphFor(kind);
    final left = centreX - space * (g.swX + g.neX) / 2;
    // The ink bottom is baseline - swY * space on screen.
    final baseline = topInkY - ornamentGapSp * space + g.swY * space;
    return Offset(left, baseline);
  }

  /// Y of the wavy trill line: the vertical middle of the trill glyph.
  static double trillLineY(Offset trillOrigin, double space) =>
      trillOrigin.dy - space * (trill.swY + trill.neY) / 2;

  /// Start and end of the wavy trill line, from the trill glyph to the
  /// notehead of the next onset in the same hand. Null when there is too little
  /// room for a visible wave.
  static ({Offset from, Offset to})? trillLineEnds({
    required Offset trillOrigin,
    required double nextHeadLeftX,
    required double space,
  }) {
    final y = trillLineY(trillOrigin, space);
    final from = Offset(
      trillOrigin.dx + space * trill.neX + space * trillLineStartGapSp,
      y,
    );
    final to = Offset(nextHeadLeftX - space * trillLineEndGapSp, y);
    if (to.dx - from.dx < minTrillLineSp * space) return null;
    return (from: from, to: to);
  }

  /// Points of a generated sine wave from [from] to [to]. The wave starts and
  /// ends on the line through both points and has a whole number of periods
  /// (at least one), so the stretch is continuous at both ends.
  static List<Offset> wavePoints({
    required Offset from,
    required Offset to,
    required double space,
    int samplesPerWave = 8,
  }) {
    final length = to.dx - from.dx;
    final waves = math.max(1, (length / (waveLengthSp * space)).round());
    final steps = waves * samplesPerWave;
    final amp = waveAmplitudeSp * space;
    return [
      for (var k = 0; k <= steps; k++)
        Offset(
          from.dx + length * k / steps,
          from.dy + amp * math.sin(2 * math.pi * k / samplesPerWave),
        ),
    ];
  }

  /// Leftmost ink of a chord: an accidental moves it left of its notehead.
  static double leftmostInk({
    required Iterable<({double headX, bool hasAccidental})> notes,
    required double space,
  }) {
    var left = double.infinity;
    for (final n in notes) {
      final x = n.hasAccidental ? n.headX - space * accidentalWidthSp : n.headX;
      left = math.min(left, x);
    }
    return left;
  }

  /// Left ink edge of a grace notehead that sits before a chord whose leftmost
  /// ink is [leftmostInkX].
  static double graceHeadLeftX({
    required double leftmostInkX,
    required double space,
  }) => leftmostInkX - space * (graceGapSp + headWidthSp * graceScale);

  /// Left origin of a grace accidental, left of the grace head at [graceLeftX].
  static double graceAccidentalX({
    required double graceLeftX,
    required double space,
  }) =>
      graceLeftX -
      space * (accidentalWidthSp * graceScale + graceAccidentalGapSp);

  /// Stem length of a grace note (standard stem scaled by [graceScale]).
  static double graceStemLength(double space) =>
      stemLengthSp * graceScale * space;

  /// X of a stem-up grace stem: on the right edge of its head.
  static double graceStemX({
    required double graceLeftX,
    required double space,
  }) =>
      graceLeftX + headWidthSp * graceScale * space - graceStemWidth(space) / 2;

  /// Stroke width of a grace stem, at least one pixel.
  static double graceStemWidth(double space) =>
      math.max(1.0, 0.1 * graceScale * space);

  /// Baseline-left origin of the grace slash, centred on the stem between
  /// [stemFromY] (head) and [stemToY] (tip), at [graceScale] size.
  static Offset slashOrigin({
    required double stemX,
    required double stemFromY,
    required double stemToY,
    required double space,
  }) {
    final s = graceScale * space;
    final cy = (stemFromY + stemToY) / 2;
    final left = stemX - s * (slash.swX + slash.neX) / 2;
    final baseline = cy + s * (slash.swY + slash.neY) / 2;
    return Offset(left, baseline);
  }
}
