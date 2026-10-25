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

/// Ornament, trill and acciaccatura geometry. Pure functions, no painting state.
///
/// Source of every number. Paths are relative to
/// `references/MuseScore/src/engraving`; `v450` is
/// `data/styles/legacy-style-defaults-v450.mss` (line numbers given). Font
/// values are read from `app/assets/fonts/Leland.otf` (1 sp = 250 font units).
/// A constant without a source is a local choice and is marked as such.
///
/// Glyph codepoints are SMuFL names (`fonts/smufl/glyphnames.json`, checked
/// against the cmap of Leland.otf). Bounding boxes are from the font.
abstract final class OrnamentLayout {
  // ---------------------------------------------------------------------------
  // Glyphs (Leland.otf bounding boxes, staff spaces)
  // ---------------------------------------------------------------------------

  /// `ornamentTrill` (U+E566): bbox x -0.048..1.532, y 0..1.532 sp.
  static const trill = OrnamentGlyph(
    '\uE566',
    swX: -0.048,
    swY: 0.0,
    neX: 1.532,
    neY: 1.532,
  );

  /// `wiggleTrill` (U+EAA4): one fill symbol of a trill's wavy line,
  /// bbox x -0.108..0.948, y 0.468..1.124 sp.
  static const wiggle = OrnamentGlyph(
    '\uEAA4',
    swX: -0.108,
    swY: 0.468,
    neX: 0.948,
    neY: 1.124,
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

  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------

  /// Ink width of `noteheadBlack` (U+E0A4, bbox x 0..1.300 sp). MuseScore's
  /// `Score::noteHeadWidth` is the font width of this glyph
  /// (`palettescoreprovider.cpp:64`).
  static const headWidthSp = 1.3;

  /// Half the ink height of `noteheadBlack` (bbox y -0.532..0.528 sp), so
  /// `2 * headHalfHeightSp` is MuseScore's `Note::headHeight` (used at
  /// `chordlayout.cpp:1048`).
  static const headHalfHeightSp = 0.53;

  /// `accidentalNoteDistance` (`v450:174`, 0.25 sp): gap between an accidental
  /// and its notehead. Scaled by the chord mag (`tdraw.cpp:2618`).
  static const accidentalNoteDistanceSp = 0.25;

  /// `graceNoteMag` (`v450:376`, 0.7; default `style/styledef.cpp:524`). Scale
  /// of a grace chord against the main chord: `chord.cpp:2071`, and
  /// `chordlayout.cpp:621`.
  static const graceNoteMag = 0.7;

  /// `stemLength` (`v450:151`, 3.5 sp). MuseScore counts it in quarter spaces,
  /// `stemlayout.cpp:60`. The stem is laid out in the chord's mag
  /// (`tlayout.cpp:5319`, `5323`), so a grace stem is `stemLengthSp * graceNoteMag`.
  static const stemLengthSp = 3.5;

  /// `stemWidth` (`v450:149`, 0.1 sp). A grace stem is `stemWidth * mag`
  /// (`tdraw.cpp:2608`).
  static const stemWidthSp = 0.1;

  /// `minNoteDistance` (`v450:156`, 0.5 sp). Clearance between a grace chord
  /// and the main chord it leans on (`chordlayout.cpp:626`, `:631`). The
  /// built-in default is 0.35 (`style/styledef.cpp:271`). This project uses
  /// the v450 value, 0.5, as a local choice.
  static const minNoteDistanceSp = 0.5;

  /// `graceToMainNoteDist` (`v450:377`, 0.45 sp). Minimum padding between a
  /// grace note and a main note in horizontal spacing
  /// (`horizontalspacing.cpp:1517`, `:1520`). Taken with the larger of the two
  /// in [graceHeadLeftX].
  static const graceToMainNoteDistSp = 0.45;

  /// `propertyDistanceHead` (`v450:193`, 0.4 sp). Gap between a note and an
  /// articulation or ornament above it (`chordlayout.cpp:1045`, `:1077`).
  static const propertyDistanceHeadSp = 0.4;

  /// `propertyDistanceStem` (`v450:194`, 0.4 sp). Gap between a stem tip and an
  /// articulation or ornament above it (`chordlayout.cpp:1044`, `:1077`).
  static const propertyDistanceStemSp = 0.4;

  /// `propertyDistance` (`v450:195`, 0.4 sp). Gap between the staff top line and
  /// an articulation above the staff (`chordlayout.cpp:1043`, `:1051`).
  static const propertyDistanceSp = 0.4;

  /// `trillPosAbove` y (`v450:266`, -0.5 sp). Default trill position relative
  /// to the staff top line (`dom/trill.cpp:426`).
  static const trillPosAboveSp = -0.5;

  /// `trillMinDistance` (`v450:1552`, 0.5 sp). Clearance the trill keeps from
  /// the chord (`dom/trill.cpp:324`, `rendering/score/autoplace.cpp:141`).
  static const trillMinDistanceSp = 0.5;

  /// Right end of a trill line: one spatium before the next onset
  /// (`dom/trill.cpp:300`, `x = segment.x - spatium`).
  static const trillEndGapSp = 1.0;

  /// Advance of `ornamentTrill` (U+E566, 433 units = 1.732 sp). The fills start
  /// after it (`dom/trill.cpp:83`).
  static const trillStartAdvanceSp = 1.732;

  /// Advance of `wiggleTrill` (U+EAA4, 220 units = 0.88 sp). Each fill adds
  /// this much (`dom/trill.cpp:84`).
  static const trillFillAdvanceSp = 0.88;

  /// `stemSlashPosition` (`v450:170`, 2 sp). Distance of the slash below the
  /// stem tip, before the reduction (`tlayout.cpp:5409`).
  static const stemSlashPositionSp = 2.0;

  /// `stemSlashAngle` (`v450:171`, 40 degrees). Angle of the slash
  /// (`tlayout.cpp:5404`).
  static const stemSlashAngleDeg = 40.0;

  /// `stemSlashThickness` (`v450:172`, 0.125 sp). Slash stroke, scaled by the
  /// grace mag (`tlayout.cpp:5443`).
  static const stemSlashThicknessSp = 0.125;

  /// Height reduction of the slash position when the note has no hook
  /// (`tlayout.cpp:5394`, `5410`).
  static const slashNoHookReduction = 0.66;

  /// Local choice: the thinnest stroke drawn for a grace stem or slash, so it
  /// stays visible at small sizes. MuseScore has no such floor.
  static const minStrokePx = 1.0;

  /// Widths of the written accidentals, from the Leland.otf bboxes: sharp
  /// U+E262 0.976 sp, flat U+E260 0.812 sp, natural U+E261 0.684 sp. MuseScore
  /// uses the symbol width of each accidental (`tdraw.cpp:2618`), so the width
  /// is the font's, not a MuseScore constant.
  static double accidentalWidth(String? accidental) => switch (accidental) {
    'sharp' => 0.976,
    'flat' => 0.812,
    'natural' => 0.684,
    _ => 0.0,
  };

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Mordent and turn
  // ---------------------------------------------------------------------------

  /// Top of the chord that a mordent or turn sits above, as MuseScore's
  /// `ChordLayout::layoutArticulations` computes it (`chordlayout.cpp:1048`
  /// to `:1077`). A stem-up chord uses its stem tip minus
  /// [propertyDistanceStemSp]. Otherwise it uses the top notehead minus
  /// [propertyDistanceHeadSp].
  static double ornamentChordTopY({
    required bool stemUp,
    required double stemTipY,
    required double topHeadY,
    required double space,
  }) => stemUp
      ? stemTipY - propertyDistanceStemSp * space
      : topHeadY - headHalfHeightSp * space - propertyDistanceHeadSp * space;

  /// Baseline of a mordent or turn: the higher of the staff clearance and the
  /// chord clearance (`chordlayout.cpp:1051`, `:1111`, `:1138`). A low chord
  /// keeps the ornament above the staff, at [propertyDistanceSp] above
  /// [staffTopY]. [staffTopY] is the top line of the staff, screen y.
  static double ornamentBaselineY({
    required double staffTopY,
    required double chordTopY,
    required double space,
  }) => math.min(staffTopY - propertyDistanceSp * space, chordTopY);

  /// Baseline-left origin of a mordent or turn centred on [centreX]. The glyph
  /// is centred on its bounding box. MuseScore centres on the optical centre
  /// (`chordlayout.cpp:1148`), which is not modelled here.
  static Offset ornamentOrigin({
    required OrnamentKind kind,
    required double centreX,
    required double baselineY,
    required double space,
  }) {
    final g = glyphFor(kind);
    final left = centreX - space * (g.swX + g.neX) / 2;
    return Offset(left, baselineY);
  }

  // ---------------------------------------------------------------------------
  // Trill
  // ---------------------------------------------------------------------------

  /// Baseline of a trill. It starts at the default position, [trillPosAboveSp]
  /// from [staffTopY], and autoplace lifts it so it clears the chord by
  /// [trillMinDistanceSp] (`autoplace.cpp:109-116`). [topInkY] is the top of
  /// the chord's ink.
  static double trillBaselineY({
    required double staffTopY,
    required double topInkY,
    required double space,
  }) => math.min(
    staffTopY + trillPosAboveSp * space,
    topInkY - trillMinDistanceSp * space,
  );

  /// Right end of a trill line for an onset at [nextOriginX]
  /// (`dom/trill.cpp:300`).
  static double trillEndX({
    required double nextOriginX,
    required double space,
  }) => nextOriginX - trillEndGapSp * space;

  /// The symbols of a trill line from [startX] to [endX], as MuseScore's
  /// `TrillSegment::symbolLine` builds them (`dom/trill.cpp:73-91`). The start
  /// glyph `ornamentTrill` sits at [startX]. The number of `wiggleTrill` fills
  /// is `lrint((w - w1) / w2)` with `w = endX - startX`, `w1` the start advance
  /// and `w2` the fill advance, clamped at zero. Fill i is at `startX + w1 +
  /// i * w2`.
  ///
  /// Note: Dart's `round()` rounds halves away from zero. `lrint` rounds halves
  /// to even. The two differ only when `(w - w1) / w2` ends in exactly .5.
  static ({double startX, List<double> fillXs}) trillSymbols({
    required double startX,
    required double endX,
    required double space,
  }) {
    final w = endX - startX;
    final w1 = trillStartAdvanceSp * space;
    final w2 = trillFillAdvanceSp * space;
    final n = math.max(0, ((w - w1) / w2).round());
    return (
      startX: startX,
      fillXs: [for (var i = 0; i < n; i++) startX + w1 + i * w2],
    );
  }

  // ---------------------------------------------------------------------------
  // Acciaccatura (grace note with stem slash)
  // ---------------------------------------------------------------------------

  /// Left ink edge of the main chord: the leftmost notehead, or the
  /// accidental in front of it. An accidental sits [accidentalNoteDistanceSp]
  /// plus its width to the left of its notehead (`tdraw.cpp:2618`).
  static double leftmostInk({
    required Iterable<({double headX, String? accidental})> notes,
    required double space,
  }) {
    var left = double.infinity;
    for (final n in notes) {
      final w = accidentalWidth(n.accidental);
      final x = n.accidental == null
          ? n.headX
          : n.headX - space * (accidentalNoteDistanceSp + w);
      left = math.min(left, x);
    }
    return left;
  }

  /// Left ink edge of a grace notehead that sits before a chord whose leftmost
  /// ink is [leftmostInkX]. The gap is the larger of [minNoteDistanceSp] and
  /// [graceToMainNoteDistSp]. The grace head is [graceNoteMag] times the main
  /// head width.
  static double graceHeadLeftX({
    required double leftmostInkX,
    required double space,
  }) =>
      leftmostInkX -
      space *
          (math.max(minNoteDistanceSp, graceToMainNoteDistSp) +
              headWidthSp * graceNoteMag);

  /// Left origin of a grace accidental, left of the grace head at
  /// [graceLeftX]. The gap and the accidental are scaled by [graceNoteMag]
  /// (`tdraw.cpp:2618`).
  static double graceAccidentalX({
    required double graceLeftX,
    required String accidental,
    required double space,
  }) =>
      graceLeftX -
      space *
          graceNoteMag *
          (accidentalWidth(accidental) + accidentalNoteDistanceSp);

  /// X where a grace note's stem attaches, the right edge of its head. A
  /// local choice: MuseScore attaches the stem at the font's `stemUpSE` anchor,
  /// which is not in the repository.
  static double graceStemRightX({
    required double graceLeftX,
    required double space,
  }) => graceLeftX + headWidthSp * graceNoteMag * space;

  /// Stem length of a grace note (`stemLengthSp` scaled by [graceNoteMag]).
  static double graceStemLength(double space) =>
      stemLengthSp * graceNoteMag * space;

  /// Stroke width of a grace stem: `stemWidth * mag` (`tdraw.cpp:2608`), and at
  /// least [minStrokePx].
  static double graceStemWidth(double space) =>
      math.max(minStrokePx, stemWidthSp * graceNoteMag * space);

  /// X of the centre of a stem-up grace stem. The stroke is centred inside its
  /// head width so that the stem's right edge is [graceStemRightX].
  static double graceStemX({
    required double graceLeftX,
    required double space,
  }) =>
      graceStemRightX(graceLeftX: graceLeftX, space: space) -
      graceStemWidth(space) / 2;

  /// The slash through the stem of a stem-up grace note, as MuseScore's
  /// `TLayout::layoutStemSlash` lays it out (`tlayout.cpp:5378`). The slash is
  /// a line, not a glyph. It applies to a note with no hook or beam, so the
  /// reduction is [slashNoHookReduction].
  ///
  /// [stemRightX] is the right edge of the stem. [stemTipY] is the stem tip,
  /// screen y. The result is the line from [from] to [to], with a stroke of
  /// [width]. `up` is -1 for a stem-up note (`tlayout.cpp:5399`), so the start
  /// lies below the tip and the line rises to the right.
  static ({Offset from, Offset to, double width}) stemSlash({
    required double stemRightX,
    required double stemTipY,
    required double space,
  }) {
    const mag = graceNoteMag;
    final headHalfWidth = headWidthSp * mag * space / 2;
    // leftHang = noteHeadWidth * mag / 2 (`tlayout.cpp:5403`).
    final startX = stemRightX - headHalfWidth;
    // startY = stemTipY - up * mag * stemSlashPosition * reduction (`:5409`).
    final startY =
        stemTipY + mag * stemSlashPositionSp * space * slashNoHookReduction;
    // The stem width is subtracted so the slash is centred on the stem
    // (`tlayout.cpp:5437`).
    final rightHang = headHalfWidth - stemWidthSp * mag * space;
    final endX = stemRightX + rightHang;
    final tan = math.tan(stemSlashAngleDeg * math.pi / 180);
    // endY = startY + up * (endX - startX) * tan(angle) (`:5439`).
    final endY = startY - (endX - startX) * tan;
    return (
      from: Offset(startX, startY),
      to: Offset(endX, endY),
      width: math.max(minStrokePx, stemSlashThicknessSp * mag * space),
    );
  }
}
