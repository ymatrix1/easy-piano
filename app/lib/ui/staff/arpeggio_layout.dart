import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Arpeggio direction: a plain wiggle, or a wiggle with an arrowhead.
enum ArpeggioDirection { plain, up, down }

/// An arpeggio on the chord at [beat] (`{arp}`, `{arp:up}`, `{arp:down}`).
class StaffArpeggio {
  const StaffArpeggio(
    this.beat, {
    this.direction = ArpeggioDirection.plain,
    this.leftHand = false,
  });

  /// Onset of the chord, same timeline as [StaffNote.beat].
  final double beat;
  final ArpeggioDirection direction;

  /// True when the directive sits in a left-hand (`LH`) bar.
  final bool leftHand;
}

/// A glissando from the notes at [startBeat] to the next onset of the same
/// hand at [endBeat] (`{gliss}`).
class StaffGlissando {
  const StaffGlissando({
    required this.startBeat,
    required this.endBeat,
    this.leftHand = false,
  });

  final double startBeat;
  final double endBeat;
  final bool leftHand;
}

/// One glyph of an arpeggio: drawn with its baseline-left point at [origin]
/// and rotated by [angle] radians about that point.
class ArpeggioGlyph {
  const ArpeggioGlyph(this.glyph, this.origin, this.angle);

  final String glyph;
  final Offset origin;
  final double angle;
}

/// Arpeggio and glissando geometry. Pure functions, no painting state.
///
/// Follows MuseScore `rendering/score/arpeggiolayout.cpp` and
/// `rendering/score/tlayout.cpp` (`layoutArpeggio`, `layoutGlissandoSegment`).
/// Every constant names its source. Values in staff spaces (sp).
///
/// Font metrics come from `app/assets/fonts/Leland.otf` (font units / 250 =
/// sp, em = 4 sp). Style values come from
/// `references/MuseScore/src/engraving/data/styles/legacy-style-defaults-v450.mss`.
abstract final class ArpeggioLayout {
  // --- Glyphs (SMuFL, MuseScore `glyphnames.json`) -------------------------

  /// `wiggleArpeggiatoUp` U+EAA9: one wiggle segment. Advance 220 units.
  static const wiggleGlyph = '\uEAA9';

  /// `wiggleArpeggiatoUpArrow` U+EAAD: wiggle with arrowhead. Advance 259.
  /// MuseScore uses this one for both UP (rotated -90) and DOWN (rotated +90)
  /// (`tlayout.cpp` layoutArpeggio, the `UP` and `DOWN` cases).
  static const arrowGlyph = '\uEAAD';

  /// Advance of [wiggleGlyph] in sp (`uniEAA9` advance 220 / 250). Each fill
  /// glyph moves the column by this much.
  static const wiggleAdvanceSp = 0.88;

  /// Advance of [arrowGlyph] in sp (`uniEAAD` advance 259 / 250).
  static const arrowAdvanceSp = 1.036;

  /// Ink left of the wiggle glyph along its advance, in sp (`uniEAA9` bounds
  /// x -22 units / 250). Font bounds, see the comment in [layoutGlyphs].
  static const _wiggleInkMinX = -0.088;

  // --- Notehead (Leland `uniE0A4`, black notehead) -------------------------

  /// Black notehead height: bounds y -133..132 units = 1.06 sp.
  static const headHeightSp = 1.06;

  /// Black notehead width: advance 325 units = 1.3 sp.
  static const headWidthSp = 1.3;

  // --- Spacing (legacy-style-defaults-v450.mss) ----------------------------

  /// `arpeggioNoteDistance` = 0.4 sp (line 441). Padding ARPEGGIO-NOTE in
  /// `paddingtable.cpp:166`, used as the gap to the notehead.
  static const noteDistanceSp = 0.4;

  /// `arpeggioAccidentalDistance` = 0.3 sp (line 442). Padding
  /// ARPEGGIO-ACCIDENTAL in `paddingtable.cpp:168`.
  static const accidentalDistanceSp = 0.3;

  /// Left edge of an accidental relative to its notehead, in sp. Matches the
  /// accidental offset used by `StaffPainter` (`space * 1.3`).
  static const accidentalWidthSp = 1.3;

  // --- Vertical extent (`ArpeggioLayout::calcTop`, arpeggiolayout.cpp) ----

  /// Extra rise when the top note sits on a space and the bottom note sits
  /// on a space too (`arpeggiolayout.cpp:346`, `0.4 * spatium`).
  static const topRiseDownSpaceSp = 0.4;

  /// Extra rise when the top note sits on a space and the bottom note on a
  /// line (`arpeggiolayout.cpp:348`, `0.25 * spatium`).
  static const topRiseDownLineSp = 0.25;

  /// Bottom staff line index in MuseScore numbering (5 lines: 0..8).
  static const _bottomLine = 8;

  // --- Glissando (legacy-style-defaults-v450.mss) --------------------------

  /// `glissandoLineWidth` = 0.15 sp (line 1169).
  static const glissandoWidthSp = 0.15;

  /// `glissandoText` = "gliss." (line 1170), shown (`glissandoShowText` 1).
  static const glissandoLabel = 'gliss.';

  // --- Horizontal placement ------------------------------------------------

  /// Right edge of the arpeggio's ink, relative to its origin, for each
  /// direction. Used to right-align the column so the arrowhead does not
  /// cross the chord. Plain: wiggle x max = 0. Up: arrow x max = 0.332
  /// (arrow ink min x mirrored). Down: arrow x max = 1.04 (see [_inkRightSp]).
  static double _inkRightSp(ArpeggioDirection d) => switch (d) {
    ArpeggioDirection.plain => 0.0,
    ArpeggioDirection.up => 0.332,
    ArpeggioDirection.down => 1.04,
  };

  /// Right edge of the arpeggio column given the chord's noteheads: the
  /// column must sit [noteDistanceSp] left of every notehead and
  /// [accidentalDistanceSp] left of every accidental (the notes' shape is
  /// spaced by `chordlayout.cpp:207`, accidentals by `arpeggiolayout.cpp`
  /// `clearAccidentals`). Takes the leftmost of those limits.
  static double rightEdge({
    required Iterable<({double headX, bool hasAccidental})> notes,
    required double space,
  }) {
    var edge = double.infinity;
    for (final n in notes) {
      edge = math.min(edge, n.headX - noteDistanceSp * space);
      if (n.hasAccidental) {
        final accLeft = n.headX - accidentalWidthSp * space;
        edge = math.min(edge, accLeft - accidentalDistanceSp * space);
      }
    }
    return edge;
  }

  /// Top and bottom of the arpeggio column, in screen y.
  ///
  /// Starts at the highest notehead's top edge and ends at the lowest
  /// notehead's bottom edge (`computeHeight`, arpeggiolayout.cpp:310-320).
  /// [topLine] / [bottomLine] are staff line indices (0 = top staff line,
  /// odd = space); see [staffLine]. A top note on a space rises by
  /// [topRiseDownSpaceSp] or [topRiseDownLineSp] (`calcTop`).
  static ({double top, double bottom}) verticalBounds({
    required double highestHeadY,
    required double lowestHeadY,
    required int topLine,
    required int bottomLine,
    required double space,
  }) {
    final half = headHeightSp * space / 2;
    var top = highestHeadY - half;
    final bottom = lowestHeadY + half;
    final onSpace = topLine > 0 && topLine < _bottomLine && topLine.isOdd;
    if (onSpace) {
      final downOnSpace = bottomLine.isOdd && bottomLine < _bottomLine;
      top -= (downOnSpace ? topRiseDownSpaceSp : topRiseDownLineSp) * space;
    }
    return (top: top, bottom: bottom);
  }

  /// Staff line index of a diatonic step, 0 = top staff line, counting down.
  /// [topLineStep] is the diatonic step of the top staff line of the hand's
  /// staff (treble F5 = step 38, bass A3 = step 26, see `StaffPainter`).
  static int staffLine({required int step, required int topLineStep}) =>
      topLineStep - step;

  /// Glyphs of one arpeggio column, from [top] to [bottom] (screen y grows
  /// downwards), right-aligned to [rightEdge].
  ///
  /// Mirrors `TLayout::layoutArpeggio`'s `symbolLine`: the number of fill
  /// glyphs is `round((h - endAdvance) / fillAdvance)`, then one end glyph.
  /// Plain and up are rotated -90 degrees and stack upwards from the bottom
  /// (arrow last, at the top). Down is rotated +90 and stacks downwards from
  /// the top (arrow last, at the bottom). `tdraw.cpp` `draw(Arpeggio)`.
  static List<ArpeggioGlyph> layoutGlyphs({
    required ArpeggioDirection direction,
    required double top,
    required double bottom,
    required double rightEdge,
    required double space,
  }) {
    final isDown = direction == ArpeggioDirection.down;
    final angle = isDown ? math.pi / 2 : -math.pi / 2;
    final endGlyph = direction == ArpeggioDirection.plain
        ? wiggleGlyph
        : arrowGlyph;
    final endAdvance = direction == ArpeggioDirection.plain
        ? wiggleAdvanceSp
        : arrowAdvanceSp;

    final h = (bottom - top) / space;
    final fills = math.max(0, ((h - endAdvance) / wiggleAdvanceSp).round());

    final x = rightEdge - _inkRightSp(direction) * space;
    // Rotated -90 (up): the first glyph's ink bottom is `origin + 0.088 sp`,
    // so the origin sits 0.088 sp above `bottom`. Rotated +90 (down): the
    // ink top is `origin - 0.088 sp`, so the origin sits 0.088 sp below `top`.
    final origin0 = isDown
        ? top - _wiggleInkMinX * space
        : bottom + _wiggleInkMinX * space;
    final step = (isDown ? 1 : -1) * wiggleAdvanceSp * space;

    final out = <ArpeggioGlyph>[];
    for (var k = 0; k < fills; k++) {
      out.add(ArpeggioGlyph(wiggleGlyph, Offset(x, origin0 + step * k), angle));
    }
    // The end glyph follows the fills, one fill advance further on.
    out.add(ArpeggioGlyph(endGlyph, Offset(x, origin0 + step * fills), angle));
    return out;
  }

  /// Glissando endpoints between two noteheads. Starts at the right edge of
  /// the start head and ends at the left edge of the end head (no padding
  /// is applied: none is given in the style). Returns null when the target is
  /// not to the right of the start.
  static ({Offset from, Offset to})? glissandoEnds({
    required Offset startHead,
    required Offset endHead,
    required double space,
  }) {
    final from = Offset(startHead.dx + headWidthSp * space, startHead.dy);
    final to = Offset(endHead.dx, endHead.dy);
    if (to.dx <= from.dx) return null;
    return (from: from, to: to);
  }

  /// Centre of the `gliss.` label: the line's midpoint, lifted above it.
  /// The offset is a placeholder: MuseScore's label placement is not read yet.
  static Offset glissandoLabelCentre({
    required Offset from,
    required Offset to,
    required double space,
  }) => Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2 - space * 1.2);

  /// Pair of noteheads (start, end) that a glissando joins: the two notes
  /// closest in pitch, so the line runs as short as possible. Returns null
  /// when either chord is empty. Not a MuseScore rule; it is a local choice.
  static (int, int)? closestPair(List<int> startPitches, List<int> endPitches) {
    if (startPitches.isEmpty || endPitches.isEmpty) return null;
    (int, int)? best;
    var bestGap = 1 << 30;
    for (var i = 0; i < startPitches.length; i++) {
      for (var j = 0; j < endPitches.length; j++) {
        final gap = (startPitches[i] - endPitches[j]).abs();
        if (gap < bestGap) {
          bestGap = gap;
          best = (i, j);
        }
      }
    }
    return best;
  }
}
