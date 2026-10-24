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
}
