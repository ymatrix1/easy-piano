import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Engraving decorations: ties, slurs, and articulation marks.
/// Styled according to MuseScore engraving principles (slurtielayout.cpp, articulation.cpp).
abstract final class EngravingDecorations {
  /// Draws a curved, tapering tie connecting two notes of the same pitch.
  static void drawTie(
    Canvas canvas, {
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    required double space,
    required Color color,
    required bool tieAbove,
  }) {
    final startX = x1 + space * 0.7;
    final endX = x2 + space * 0.5;
    if (endX <= startX) return;

    final midX = (startX + endX) / 2;
    final curveH = space * 0.55 * (tieAbove ? -1 : 1);
    final y = (y1 + y2) / 2 + (tieAbove ? -space * 0.5 : space * 0.5);

    // Tapering arc: thickest in the center (~0.25 space), ending in points.
    final path = Path()
      ..moveTo(startX, y)
      ..quadraticBezierTo(midX, y + curveH, endX, y)
      ..quadraticBezierTo(midX, y + curveH * 0.65, startX, y)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  /// Draws an articulation mark (staccato, tenuto, accent) positioned relative to notehead.
  static void drawArticulation(
    Canvas canvas, {
    required String articulation,
    required double x,
    required double y,
    required double space,
    required Color color,
    required bool stemDown,
  }) {
    final cx = x + space * 0.65;
    // Articulation sits opposite to the stem direction unless specified.
    final artY = stemDown ? y - space * 0.9 : y + space * 0.9;

    switch (articulation) {
      case 'staccato':
        canvas.drawCircle(
          Offset(cx, artY),
          space * 0.15,
          Paint()..color = color,
        );
      case 'tenuto':
        canvas.drawLine(
          Offset(cx - space * 0.45, artY),
          Offset(cx + space * 0.45, artY),
          Paint()
            ..color = color
            ..strokeWidth = math.max(1.2, space * 0.12)
            ..strokeCap = StrokeCap.round,
        );
      case 'accent':
        final p = Path()
          ..moveTo(cx - space * 0.4, artY - space * 0.25)
          ..lineTo(cx + space * 0.4, artY)
          ..lineTo(cx - space * 0.4, artY + space * 0.25);
        canvas.drawPath(
          p,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.2, space * 0.12)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
    }
  }

  /// Draws a classical grand staff curly brace ({) connecting treble and bass staves,
  /// matching MuseScore Studio (bracket.cpp / tlayout.cpp) and Gould rules.
  static void drawGrandStaffBrace(
    Canvas canvas, {
    required double systemX,
    required double staffTop,
    required double staffBottom,
    required double space,
    required Color color,
  }) {
    final midY = (staffTop + staffBottom) / 2;
    // Classical Gould engraving: brace extends 0.5 space above top line and below bottom line
    final h2 = ((staffBottom - staffTop) + space * 1.0) / 2;
    final braceW = space * 1.35;

    double bx(double a) => systemX + (a / 560.0) * braceW - space * 0.15;
    double by(double a) => midY + (a / 7024.0) * h2;

    final brace = Path()
      ..moveTo(bx(-8), by(-2048))
      ..cubicTo(bx(-8), by(-3192), bx(-360), by(-4304), bx(-360), by(-5400))
      ..cubicTo(bx(-360), by(-5952), bx(-264), by(-6488), bx(32), by(-6968))
      ..cubicTo(bx(36), by(-6974), bx(38), by(-6984), bx(38), by(-6990))
      ..cubicTo(bx(38), by(-7008), bx(16), by(-7024), bx(0), by(-7024))
      ..cubicTo(bx(-8), by(-7024), bx(-22), by(-7022), bx(-32), by(-7008))
      ..cubicTo(bx(-416), by(-6392), bx(-544), by(-5680), bx(-544), by(-4960))
      ..cubicTo(bx(-544), by(-3800), bx(-168), by(-2680), bx(-168), by(-1568))
      ..cubicTo(bx(-168), by(-1016), bx(-264), by(-496), bx(-560), by(-16))
      ..lineTo(bx(-560), by(0))
      ..lineTo(bx(-560), by(16))
      ..cubicTo(bx(-264), by(496), bx(-168), by(1016), bx(-168), by(1568))
      ..cubicTo(bx(-168), by(2680), bx(-544), by(3800), bx(-544), by(4960))
      ..cubicTo(bx(-544), by(5680), bx(-416), by(6392), bx(-32), by(7008))
      ..cubicTo(bx(-22), by(7022), bx(-8), by(7024), bx(0), by(7024))
      ..cubicTo(bx(16), by(7024), bx(38), by(7008), bx(38), by(6990))
      ..cubicTo(bx(38), by(6984), bx(36), by(6974), bx(32), by(6968))
      ..cubicTo(bx(-264), by(6488), bx(-360), by(5952), bx(-360), by(5400))
      ..cubicTo(bx(-360), by(4304), bx(-8), by(3192), bx(-8), by(2048))
      ..cubicTo(bx(-8), by(1320), bx(-136), by(624), bx(-512), by(0))
      ..cubicTo(bx(-136), by(-624), bx(-8), by(-1320), bx(-8), by(-2048))
      ..close();

    canvas.drawPath(
      brace,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }
}
