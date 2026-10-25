import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:easy_piano/ui/staff/dynamics_layout.dart';

/// A damper pedal span: pressed at [startBeat], released at [endBeat].
///
/// [changeBeats] are the beats inside the span where the pedal is pressed
/// again without a release (a pedal change). [released] is false when the
/// span runs to the end of the song and never lifts.
class StaffPedal {
  const StaffPedal({
    required this.startBeat,
    required this.endBeat,
    this.changeBeats = const [],
    this.released = true,
  });

  final double startBeat;
  final double endBeat;
  final List<double> changeBeats;
  final bool released;
}

/// Pedal geometry of one span, in canvas coordinates (y grows downwards).
class PedalGeometry {
  const PedalGeometry({
    required this.lineY,
    required this.pedX,
    required this.startX,
    required this.endX,
    required this.notchX,
    required this.released,
    required this.starX,
  });

  /// Line y: also the baseline of the `Ped.` and `*` glyphs.
  final double lineY;

  /// Left edge of the `Ped.` glyph.
  final double pedX;

  /// Where the bracket line starts, after the `Ped.` glyph.
  final double startX;

  /// Where the bracket line ends: the release hook, or the song end when open.
  final double endX;

  /// Centre x of each pedal change notch, inside (startX, endX).
  final List<double> notchX;

  final bool released;

  /// Left edge of the `*` glyph. Only meaningful when [released].
  final double starX;
}

/// Damper pedal layout. Pure functions, no painting state.
///
/// Follows MuseScore `dom/pedal.cpp` (`Pedal::linePos`, `Pedal::defaultPosSid`)
/// and `rendering/score/tlayout.cpp` (`layoutPedal`, `layoutPedalSegment`).
/// Style values come from `styledef.cpp`; glyph names from
/// `fonts/smufl/glyphnames.json`.
///
/// Notches are an approximation of MuseScore's 45-degree hooks: MuseScore
/// draws a change as the end hook of one span plus the start hook of the next,
/// which together form the inverted `V` in `___/\___`.
abstract final class PedalLayout {
  /// `keyboardPedalPed` (U+E650): `Ped.`, placed on the pedal down.
  static const pedGlyph = '\uE650';

  /// `keyboardPedalUp` (U+E655): `*`, placed after the pedal release.
  static const starGlyph = '\uE655';

  /// Style `pedalLineWidth` (0.11 sp).
  static const lineWidthSp = 0.11;

  /// Style `pedalHookHeight` (1.2 sp): height of the release hook.
  static const hookHeightSp = 1.2;

  /// Style `pedalPosBelow` y (2.5 sp): line position below the bottom staff
  /// line.
  static const posBelowSp = 2.5;

  /// Clearance from notes and other items. Reuses the dynamics clearance.
  static const minDistanceSp = DynamicsLayout.dynamicsMinDistanceSp;

  /// `Pedal::linePos`: a down-pedal starts 0.5 sp left of its note.
  static const startOffsetSp = 0.5;

  /// `Pedal::linePos`: a release ends 0.75 sp before the next note.
  static const releaseOffsetSp = 0.75;

  /// `Pedal::linePos`: a change ends 1.25 sp before the note that re-presses.
  static const changeOffsetSp = 1.25;

  /// Gap between the `Ped.` glyph and the line start.
  static const glyphGapSp = 0.2;

  /// Gap between the release hook and the `*` glyph.
  static const starGapSp = 0.1;

  /// Half width of a change notch.
  static const notchHalfWidthSp = 0.35;

  /// Height of a change notch above the line.
  static const notchHeightSp = 0.6;

  /// Y of the pedal line for a span from [x0] to [x1].
  ///
  /// Starts at the style position and moves down until the release hook (which
  /// rises [hookHeightSp] above the line) clears every obstacle it overlaps,
  /// the same autoplace rule used for dynamics.
  static double lineY({
    required double bottomStaffY,
    required double space,
    required double x0,
    required double x1,
    required Iterable<Rect> obstacles,
  }) {
    final h = hookHeightSp * space;
    final top = DynamicsLayout.clearBelow(
      top: bottomStaffY + posBelowSp * space - h,
      height: h,
      x0: x0,
      x1: x1,
      minDist: minDistanceSp * space,
      obstacles: obstacles,
    );
    return top + h;
  }

  /// Geometry of one span.
  ///
  /// [downX] is the x of the note at the pedal down. [endPointX] is the release
  /// point (already offset by [releaseOffsetSp]) or the song end when the span
  /// is not [released]. [changeX] holds one x per pedal change, already offset
  /// by [changeOffsetSp]. [pedWidth] is the width of the `Ped.` glyph.
  static PedalGeometry geometry({
    required double space,
    required double lineY,
    required double downX,
    required double endPointX,
    required bool released,
    required List<double> changeX,
    required double pedWidth,
  }) {
    final pedX = downX - startOffsetSp * space;
    final startX = pedX + pedWidth + glyphGapSp * space;
    final notches = [
      for (final x in changeX)
        if (x > startX && x < endPointX) x,
    ]..sort();
    return PedalGeometry(
      lineY: lineY,
      pedX: pedX,
      startX: startX,
      endX: endPointX,
      notchX: notches,
      released: released,
      starX: endPointX + starGapSp * space,
    );
  }

  /// Straight strokes that make up the bracket line, as polylines.
  ///
  /// The line runs from [PedalGeometry.startX] to [PedalGeometry.endX], broken
  /// at each notch, which is drawn as a `/\` polyline. A released span ends in
  /// a vertical hook up from the line.
  static List<List<Offset>> strokes(PedalGeometry g, {required double space}) {
    final y = g.lineY;
    final nw = notchHalfWidthSp * space;
    final nh = notchHeightSp * space;
    final out = <List<Offset>>[];
    var cur = g.startX;
    for (final c in g.notchX) {
      final a = c - nw;
      final b = c + nw;
      if (a > cur) out.add([Offset(cur, y), Offset(a, y)]);
      out.add([Offset(a, y), Offset(c, y - nh), Offset(b, y)]);
      cur = math.max(cur, b);
    }
    if (g.endX > cur) out.add([Offset(cur, y), Offset(g.endX, y)]);
    if (g.released) {
      out.add([Offset(g.endX, y), Offset(g.endX, y - hookHeightSp * space)]);
    }
    return out;
  }

  /// Draws [strokes] with the pedal line weight.
  static void draw(
    Canvas canvas,
    PedalGeometry g, {
    required double space,
    required Color color,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = math.max(1.0, lineWidthSp * space)
      ..strokeCap = StrokeCap.butt
      ..style = PaintingStyle.stroke;
    for (final pts in strokes(g, space: space)) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }
}
