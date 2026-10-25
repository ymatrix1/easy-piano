import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'dynamics_layout.dart';

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

/// Arpeggio and glissando geometry. Pure functions, no painting state.
///
/// Follows MuseScore `rendering/score/arpeggiolayout.cpp` (wiggle stacked
/// along the chord, arrowheads at the ends, clearance from the chord) and
/// `tlayout.cpp` (glissando line with an italic `gliss.` label).
///
/// Glyph codepoints are SMuFL names from `fonts/smufl/glyphnames.json`.
/// Metrics come from `fonts/leland/leland_metadata.json`.
abstract final class ArpeggioLayout {
  /// `wiggleArpeggiatoUp` (U+EAA9): the vertical wiggle, bbox x -0.088..0.968,
  /// y 0..0.656 staff spaces.
  static const wiggleGlyph = '\uEAA9';

  /// `wiggleArpeggiatoUpArrow` (U+EAAD): wiggle with arrowhead at the top.
  static const arrowUpGlyph = '\uEAAD';

  /// `wiggleArpeggiatoDownArrow` (U+EAAE): wiggle with arrowhead at the bottom.
  static const arrowDownGlyph = '\uEAAE';

  /// Right edge of the wiggle glyph bbox, in staff spaces.
  static const wiggleRightSp = 0.968;

  /// Height of one wiggle glyph, in staff spaces. Stacks step by this much.
  static const wiggleHeightSp = 0.656;

  /// Arrow glyph extent above the baseline (bbox NE y) and below (bbox SW y).
  static const arrowAboveSp = 1.04;
  static const arrowBelowSp = 0.332;

  /// Clearance between the wiggle and the leftmost accidental or notehead,
  /// in staff spaces (MuseScore `arpeggioNoteDistance` 0.8 sp).
  static const clearanceSp = 0.8;

  /// Half the height of a black notehead, in staff spaces. A chord's wiggle
  /// spans from its topmost to its bottommost head, each padded by this.
  static const noteheadHalfHeightSp = 0.5;

  /// Extra space the accidental takes to the left of its notehead, in staff
  /// spaces. Used by the painter to find the leftmost ink of a chord.
  static const accidentalWidthSp = 1.0;

  /// Text drawn above a glissando line.
  static const glissandoLabel = 'gliss.';

  /// Glissando line thickness, in staff spaces.
  static const glissandoWidthSp = 0.12;

  /// Gap between the note edges and the ends of a glissando line, in spaces.
  static const _glissandoEndGapSp = 0.3;

  /// Left edge of the arpeggio given the leftmost ink of its chord.
  ///
  /// The glyph origin (its baseline-left point) is placed so that the glyph's
  /// right edge sits [clearanceSp] to the left of [leftmostInkX].
  static double originX({
    required double leftmostInkX,
    required double space,
  }) => leftmostInkX - space * (clearanceSp + wiggleRightSp);

  /// Leftmost ink of a chord, given the notehead x of each note and whether
  /// it has an accidental.
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

  /// Baseline y of each wiggle glyph, stacked from [top] down to [bottom]
  /// (screen y grows downwards). Always at least one glyph.
  static List<double> wiggleBaselines({
    required double top,
    required double bottom,
    required double space,
  }) {
    final step = wiggleHeightSp * space;
    final span = math.max(0.0, bottom - top);
    final count = math.max(1, (span / step).ceil());
    // Each glyph's baseline is its bottom edge (bbox SW y = 0).
    return [for (var k = 0; k < count; k++) top + (k + 1) * step];
  }

  /// Baseline y of the arrowhead glyph. [ArpeggioDirection.up] puts the arrow
  /// above [top] (its body bottom touches the stack), down puts it below
  /// [bottom] (its body top touches the stack). Plain returns null.
  static double? arrowBaseline({
    required ArpeggioDirection direction,
    required double top,
    required double bottom,
    required double space,
  }) => switch (direction) {
    ArpeggioDirection.plain => null,
    ArpeggioDirection.up => top - arrowBelowSp * space,
    ArpeggioDirection.down => bottom + arrowAboveSp * space,
  };

  /// Glyph for [direction], or null for a plain arpeggio.
  static String? arrowGlyph(ArpeggioDirection direction) => switch (direction) {
    ArpeggioDirection.plain => null,
    ArpeggioDirection.up => arrowUpGlyph,
    ArpeggioDirection.down => arrowDownGlyph,
  };

  /// Glissando endpoints between two noteheads, leaving a small gap at each
  /// end. Returns null when the target is not to the right of the start.
  static ({Offset from, Offset to})? glissandoEnds({
    required Offset startHead,
    required Offset endHead,
    required double space,
  }) {
    final from = Offset(
      startHead.dx + DynamicsLayout.noteheadWidthSp * space / 2,
      startHead.dy,
    );
    final to = Offset(endHead.dx - _glissandoEndGapSp * space, endHead.dy);
    if (to.dx <= from.dx) return null;
    return (from: from, to: to);
  }

  /// Centre of the `gliss.` label: the line's midpoint, lifted above it.
  static Offset glissandoLabelCentre({
    required Offset from,
    required Offset to,
    required double space,
  }) => Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2 - space * 1.2);

  /// Pair of noteheads (start, end) that a glissando joins: the two notes
  /// closest in pitch, so the line runs as short as possible. Returns null
  /// when either chord is empty.
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
