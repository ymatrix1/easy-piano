import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Crescendo opens (`<`), diminuendo closes (`>`). MuseScore `HairpinType`.
enum HairpinKind { crescendo, diminuendo }

/// A dynamic mark (`p`, `mf`, `ff`, ...) anchored at [beat].
class StaffDynamic {
  const StaffDynamic(this.beat, this.mark, {this.leftHand = false});

  /// Onset in beats, same timeline as [StaffNote.beat].
  final double beat;

  /// Dynamic text, e.g. `p`, `pp`, `mf`, `sfz`. See [DynamicsLayout.glyphsFor].
  final String mark;

  /// True when the directive sits in a left-hand (`LH`) bar: it belongs to the
  /// bass staff. Right-hand dynamics belong to the treble staff.
  final bool leftHand;
}

/// A hairpin from [startBeat] to [endBeat]. Belongs to the treble staff unless
/// [leftHand] is set.
class StaffHairpin {
  const StaffHairpin({
    required this.startBeat,
    required this.endBeat,
    required this.kind,
    this.leftHand = false,
  });

  final double startBeat;
  final double endBeat;
  final HairpinKind kind;
  final bool leftHand;
}

/// Dynamics and hairpin geometry. Pure functions, no painting state.
///
/// Every rule names the MuseScore source it follows. Style values come from
/// `data/styles/legacy-style-defaults-v450.mss`; glyph metrics from
/// `fonts/bravura/bravura_metadata.json`.
abstract final class DynamicsLayout {
  // SMuFL dynamics range (U+E520 onwards). MuseScore composes every dynamic
  // from these letter glyphs (`Dynamic::DYN_LIST`), e.g. `mf` = mezzo + forte.
  static const _glyphP = '\uE520'; // dynamicPiano
  static const _glyphM = '\uE521'; // dynamicMezzo
  static const _glyphF = '\uE522'; // dynamicForte
  static const _glyphS = '\uE524'; // dynamicSforzando1
  static const _glyphZ = '\uE525'; // dynamicZ

  /// Glyph top above the baseline, in staff spaces (bbox `bBoxNE.y`).
  static const _ascentP = 1.096;
  static const _ascentF = 1.776;
  static const _ascentS = 1.092;
  static const _ascentZ = 1.072;

  /// Glyph bottom below the baseline, in staff spaces (bbox `bBoxSW.y`).
  static const _descentP = 0.568;
  static const _descentF = 0.608;

  /// `dynamicsPosBelow` y: the dynamic's top, measured from the bottom staff
  /// line. Style: `legacy-style-defaults-v450.mss` (`dynamicsPosBelow` y=2).
  static const dynamicsPosBelowSp = 2.0;

  /// `hairpinPosBelow` y: the hairpin's centre, from the bottom staff line.
  static const hairpinPosBelowSp = 1.75;

  /// `hairpinHeight`: full opening at the wide end, in staff spaces.
  static const hairpinHeightSp = 1.15;

  /// `hairpinLineWidth`.
  static const hairpinLineWidthSp = 0.12;

  /// `autoplaceHairpinDynamicsDistance`: clearance between a hairpin and a
  /// dynamic.
  static const hairpinDynamicsDistanceSp = 0.5;

  /// `dynamicsMinDistance`: clearance of a dynamic from other items.
  static const dynamicsMinDistanceSp = 0.5;

  /// `hairpinMinDistance`: clearance of a hairpin from other items.
  static const hairpinMinDistanceSp = 0.7;

  /// `engravingDefaults.thinBarlineThickness`: width of a thin barline.
  static const thinBarlineSp = 0.16;

  /// `engravingDefaults.stemThickness`.
  static const stemSp = 0.12;

  /// Black notehead bbox (`noteheadBlack`): 1.18 wide, 1.0 tall.
  static const noteheadWidthSp = 1.18;
  static const noteheadHeightSp = 1.0;

  /// Whole notehead bbox (`noteheadWhole`): 1.688 wide.
  static const noteheadWholeWidthSp = 1.688;

  /// Horizontal centre of a notehead from its left edge (MuseScore
  /// `centerOnNotehead` centres on the glyph's optical middle, so half width).
  static double noteheadCentreSp({required bool whole}) =>
      (whole ? noteheadWholeWidthSp : noteheadWidthSp) / 2;

  /// Vertical extent of a hairpin's box: the opening plus the stroke width.
  static const hairpinBoxSp = hairpinHeightSp + hairpinLineWidthSp;

  static final _marks = RegExp(r'^(p{1,3}|f{1,3}|mp|mf|fp|sfz?)$');

  /// SMuFL glyph string for [mark], or null when the mark is not supported.
  ///
  /// Supported: `p pp ppp f ff fff mp mf fp sf sfz`.
  static String? glyphsFor(String mark) {
    if (!_marks.hasMatch(mark)) return null;
    final out = StringBuffer();
    for (final c in mark.split('')) {
      out.write(switch (c) {
        'p' => _glyphP,
        'm' => _glyphM,
        'f' => _glyphF,
        's' => _glyphS,
        'z' => _glyphZ,
        _ => throw StateError('unreachable: $c'),
      });
    }
    return out.toString();
  }

  /// Height above the baseline of the tallest glyph in [mark], in spaces.
  static double ascentSp(String mark) {
    var a = _ascentP;
    if (mark.contains('f')) a = math.max(a, _ascentF);
    if (mark.contains('s')) a = math.max(a, _ascentS);
    if (mark.contains('z')) a = math.max(a, _ascentZ);
    return a;
  }

  /// Depth below the baseline of the lowest glyph in [mark], in spaces.
  static double descentSp(String mark) {
    var d = mark.contains('p') ? _descentP : 0.04;
    if (mark.contains('f')) d = math.max(d, _descentF);
    return d;
  }

  /// Full height of a dynamic's box, in spaces.
  static double boxHeightSp(String mark) => ascentSp(mark) + descentSp(mark);

  /// Centre y of a hairpin below the bottom staff line (`bottomStaffY` is the
  /// y of that line, increasing downwards).
  static double hairpinCentreY({
    required double bottomStaffY,
    required double space,
  }) => bottomStaffY + hairpinPosBelowSp * space;

  // --- Placement -----------------------------------------------------------

  /// Top of a dynamic placed below the bottom staff line, before collisions.
  /// Style `dynamicsPosBelow`.
  static double dynamicNominalTop({
    required double bottomStaffY,
    required double space,
  }) => bottomStaffY + dynamicsPosBelowSp * space;

  /// Top of a hairpin placed below the bottom staff line, before collisions.
  static double hairpinNominalTop({
    required double bottomStaffY,
    required double space,
  }) =>
      hairpinCentreY(bottomStaffY: bottomStaffY, space: space) -
      hairpinBoxSp * space / 2;

  /// Pushes a box of [height] down until it clears every obstacle it overlaps.
  ///
  /// Mirrors autoplace below (`Autoplace::autoplaceSegmentElement`): the box
  /// starts at [top] and moves down past each obstacle that is horizontally
  /// overlapping and vertically in its way, leaving [minDist] between them.
  /// Obstacles above the box are ignored. Only downward moves happen.
  static double clearBelow({
    required double top,
    required double height,
    required double x0,
    required double x1,
    required double minDist,
    required Iterable<Rect> obstacles,
  }) {
    var t = top;
    var moved = true;
    while (moved) {
      moved = false;
      for (final o in obstacles) {
        if (o.right <= x0 - minDist || o.left >= x1 + minDist) continue;
        if (o.bottom <= t - minDist || o.top >= t + height + minDist) continue;
        t = o.bottom + minDist;
        moved = true;
      }
    }
    return t;
  }

  /// Bounds of the free band between a staff pair (`centerItemGroup`).
  ///
  /// The upper bound is the bottom of the highest-reaching obstacle above
  /// [gapMidY] that overlaps [x0]..[x1]; the lower bound is the top of the
  /// lowest-reaching obstacle below it. Returns (upperBottom, lowerTop).
  static (double, double) gapEdges({
    required double x0,
    required double x1,
    required double gapMidY,
    required Iterable<Rect> obstacles,
    required double upperDefault,
    required double lowerDefault,
  }) {
    var upper = upperDefault;
    var lower = lowerDefault;
    for (final o in obstacles) {
      if (o.right <= x0 || o.left >= x1) continue;
      if (o.center.dy < gapMidY) {
        upper = math.max(upper, o.bottom);
      } else {
        lower = math.min(lower, o.top);
      }
    }
    return (upper, lower);
  }

  /// Top of a box of [height] centred in the free band between an upper
  /// bottom and a lower top, keeping [minDist] from both.
  ///
  /// Mirrors `SystemLayout::centerItemGroup`: `spaceAbove` and `spaceBelow`
  /// are the clearances minus `minDist`, and the item moves by
  /// `0.5 * (spaceBelow - spaceAbove)`. The result is the midpoint of the band.
  static double centredTop({
    required double upperBottom,
    required double lowerTop,
    required double height,
    required double minDist,
  }) {
    final free = lowerTop - upperBottom - height - 2 * minDist;
    return upperBottom + minDist + free / 2;
  }

  /// Horizontal left edge of a dynamic whose centre is [centreX]
  /// (`centerOnNotehead` in `dynamicslayout.cpp`: the text is centred).
  static double dynamicLeft({required double centreX, required double width}) =>
      centreX - width / 2;

  // --- Horizontal collisions -------------------------------------------------

  /// Horizontal shift that keeps a dynamic clear of barlines
  /// (`DynamicsLayout::manageBarlineCollisions`).
  ///
  /// [left] and [right] are the dynamic's extent. Each barline is a thin line
  /// of width [thinBarlineSp]. The nearest barline on each side is checked, and
  /// [dynamicsMinDistanceSp] is kept from it.
  static double barlineShift({
    required double left,
    required double right,
    required Iterable<double> barlineXs,
    required double space,
  }) {
    final gap = 0.25 * space; // minBarLineDistance in manageBarlineCollisions
    final half = thinBarlineSp * space / 2;
    double? ahead;
    double? behind;
    for (final x in barlineXs) {
      // Strictly after the start: a barline at the note itself is the one
      // behind it, not one the dynamic runs into.
      if (x > left && (ahead == null || x < ahead)) ahead = x;
      if (x <= left && (behind == null || x > behind)) behind = x;
    }
    var dx = 0.0;
    if (ahead != null) {
      final margin = (ahead - half) - right - gap;
      if (margin < 0) dx += margin;
    }
    if (behind != null) {
      final margin = left + dx - (behind + half) - gap;
      if (margin < 0) dx -= margin;
    }
    return dx;
  }

  // --- Hairpin drawing (tlayout.cpp layoutHairpinSegment) ----------------

  /// The two arm strokes of a hairpin (`tlayout.cpp`, SINGLE segment).
  ///
  /// Crescendo: both arms start at the tip (`x1`, centre) and open to the
  /// right, ending at `x2`. Diminuendo: both arms start open at `x1` and close
  /// into the tip at `x2`. Hairpins shorter than one space are stretched to one
  /// space, as in MuseScore.
  static List<(Offset, Offset)> hairpinSegments({
    required double x1,
    required double x2,
    required double centreY,
    required double space,
    required HairpinKind kind,
  }) {
    final end = math.max(x2, x1 + space);
    final h = hairpinHeightSp * space * 0.5;
    return switch (kind) {
      HairpinKind.crescendo => [
        (Offset(x1, centreY), Offset(end, centreY - h)),
        (Offset(x1, centreY), Offset(end, centreY + h)),
      ],
      HairpinKind.diminuendo => [
        (Offset(x1, centreY - h), Offset(end, centreY)),
        (Offset(x1, centreY + h), Offset(end, centreY)),
      ],
    };
  }

  /// Draws a hairpin with [hairpinSegments] as straight strokes.
  static void drawHairpin(
    Canvas canvas, {
    required double x1,
    required double x2,
    required double centreY,
    required double space,
    required HairpinKind kind,
    required Color color,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = math.max(1.0, hairpinLineWidthSp * space)
      ..strokeCap = StrokeCap.butt;
    for (final (a, b) in hairpinSegments(
      x1: x1,
      x2: x2,
      centreY: centreY,
      space: space,
      kind: kind,
    )) {
      canvas.drawLine(a, b, paint);
    }
  }

  /// Relative tops of items stacked inside one centred group
  /// (`SystemLayout::centerItemGroup`, convergence step).
  ///
  /// [natural] is each item's preferred top, [heights] its height and [gaps]
  /// the clearance it needs from the item stacked above it. Items are packed
  /// downwards in order of their preferred top, so none overlaps another. The
  /// result is each item's top relative to the group's first top, in input
  /// order, and the total packed height of the group.
  static (List<double>, double) stackGroup({
    required List<double> natural,
    required List<double> heights,
    required List<double> gaps,
  }) {
    final n = natural.length;
    if (n == 0) return (const [], 0);
    final base = natural.reduce(math.min);
    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) => natural[a].compareTo(natural[b]));
    final rel = List<double>.filled(n, 0);
    double? bottom;
    for (final i in order) {
      var off = natural[i] - base;
      if (bottom != null) {
        off = math.max(off, bottom - base + gaps[i]);
      }
      rel[i] = off;
      bottom = off + base + heights[i];
    }
    final height = [for (var i = 0; i < n; i++) rel[i] + heights[i]]
        .reduce(math.max);
    return (rel, height);
  }
}
