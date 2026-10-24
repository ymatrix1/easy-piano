import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Crescendo opens (`<`), diminuendo closes (`>`). MuseScore `HairpinType`.
enum HairpinKind { crescendo, diminuendo }

/// A dynamic mark (`p`, `mf`, `ff`, ...) anchored at [beat].
class StaffDynamic {
  const StaffDynamic(this.beat, this.mark);

  /// Onset in beats, same timeline as [StaffNote.beat].
  final double beat;

  /// Dynamic text, e.g. `p`, `pp`, `mf`, `sfz`. See [DynamicsLayout.glyphsFor].
  final String mark;
}

/// A hairpin from [startBeat] to [endBeat], drawn below the bottom staff.
class StaffHairpin {
  const StaffHairpin({
    required this.startBeat,
    required this.endBeat,
    required this.kind,
  });

  final double startBeat;
  final double endBeat;
  final HairpinKind kind;
}

/// Dynamics and hairpin geometry. Pure functions, no painting state.
///
/// Reference: MuseScore `rendering/score/dynamicslayout.cpp` (placement,
/// barline avoidance) and `rendering/score/tlayout.cpp:layoutHairpinSegment`
/// (two-line hairpin geometry). Default style values come from
/// `data/styles/legacy-style-defaults-v450.mss`.
abstract final class DynamicsLayout {
  // SMuFL dynamics range (U+E520 onwards). MuseScore composes every dynamic
  // from these letter glyphs (`Dynamic::DYN_LIST`), e.g. `mf` = mezzo + forte.
  // Code points checked against the bounding boxes in
  // `fonts/bravura/bravura_metadata.json`.
  static const _glyphP = '\uE520'; // dynamicPiano
  static const _glyphM = '\uE521'; // dynamicMezzo
  static const _glyphF = '\uE522'; // dynamicForte
  static const _glyphS = '\uE524'; // dynamicSforzando1
  static const _glyphZ = '\uE525'; // dynamicZ

  /// Glyph top above the baseline, in staff spaces (font bbox `bBoxNE.y`).
  static const _ascentP = 1.096;
  static const _ascentF = 1.776;
  static const _ascentS = 1.092;
  static const _ascentZ = 1.072;

  /// `dynamicsPosBelow` y, measured from the bottom staff line.
  static const dynamicsPosBelowSp = 2.0;

  /// `hairpinPosBelow` y (line centre), from the bottom staff line.
  static const hairpinPosBelowSp = 1.75;

  /// `hairpinHeight`: full opening at the wide end, in staff spaces.
  static const hairpinHeightSp = 1.15;

  /// `hairpinLineWidth`.
  static const hairpinLineWidthSp = 0.12;

  /// `autoplaceHairpinDynamicsDistance`.
  static const hairpinDynamicsDistanceSp = 0.5;

  /// `dynamicsMinDistance`, used as the clearance from barlines
  /// (`DynamicsLayout::manageBarlineCollisions` uses 0.25 sp).
  static const barlineClearanceSp = 0.25;

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

  /// Centre y of a hairpin below the bottom staff line (`bottomStaffY` is the
  /// y of that line, increasing downwards).
  static double hairpinCentreY({
    required double bottomStaffY,
    required double space,
  }) => bottomStaffY + hairpinPosBelowSp * space;

  /// Baseline y of a dynamic below the bottom staff line.
  ///
  /// MuseScore autoplace moves a dynamic below a hairpin that overlaps it in
  /// x, keeping [hairpinDynamicsDistanceSp] clearance below the hairpin.
  static double dynamicBaselineY({
    required double bottomStaffY,
    required double space,
    required String mark,
    required bool hairpinOverlaps,
  }) {
    var top = bottomStaffY + dynamicsPosBelowSp * space;
    if (hairpinOverlaps) {
      final hairpinBottom =
          hairpinCentreY(bottomStaffY: bottomStaffY, space: space) +
          hairpinHeightSp * space * 0.5;
      top = math.max(top, hairpinBottom + hairpinDynamicsDistanceSp * space);
    }
    return top + ascentSp(mark) * space;
  }

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

  /// Horizontal shift that keeps a dynamic clear of barlines
  /// (`DynamicsLayout::manageBarlineCollisions`).
  ///
  /// [left] and [right] are the dynamic's extent. Only the nearest barline on
  /// each side is checked, and the reference point is the dynamic's own
  /// bounds. Barlines are zero-width here, so the clearance is measured from
  /// their x.
  static double barlineShift({
    required double left,
    required double right,
    required Iterable<double> barlineXs,
    required double space,
  }) {
    final gap = barlineClearanceSp * space;
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
      final margin = ahead - right - gap;
      if (margin < 0) dx += margin;
    }
    if (behind != null) {
      final margin = left + dx - behind - gap;
      if (margin < 0) dx -= margin;
    }
    return dx;
  }
}
