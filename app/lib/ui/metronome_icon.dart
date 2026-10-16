import 'package:flutter/material.dart';

/// Outline metronome (trapezoid body, scale ticks, swinging arm), drawn so it
/// matches Material's rounded icons without an icon font.
class MetronomeIcon extends StatelessWidget {
  const MetronomeIcon({super.key, required this.color, this.size = 24});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _MetronomePainter(color));
}

class _MetronomePainter extends CustomPainter {
  _MetronomePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Body.
    canvas.drawPath(
      Path()
        ..moveTo(8.6 * s, 2.5 * s)
        ..lineTo(15.4 * s, 2.5 * s)
        ..lineTo(20 * s, 21.5 * s)
        ..lineTo(4 * s, 21.5 * s)
        ..close(),
      p,
    );
    // Base line.
    canvas.drawLine(Offset(5.2 * s, 17 * s), Offset(18.8 * s, 17 * s), p);
    // Scale ticks on the centre rod.
    canvas.drawLine(Offset(12 * s, 5.5 * s), Offset(12 * s, 17 * s), p);
    for (final y in [6.0, 9.0, 12.0]) {
      canvas.drawLine(Offset(10.3 * s, y * s), Offset(13.7 * s, y * s), p);
    }
    // Arm with its weight, swung right.
    canvas.drawLine(Offset(12 * s, 17 * s), Offset(21 * s, 4 * s), p);
    canvas.drawCircle(
      Offset(18.6 * s, 7.4 * s),
      1.5 * s,
      p..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_MetronomePainter old) => old.color != color;
}
