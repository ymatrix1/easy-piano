import 'package:flutter/material.dart';

import 'key_geometry.dart';

class KeyboardPainter extends CustomPainter {
  KeyboardPainter({
    required this.lowPitch,
    required this.highPitch,
    required this.pressed,
    required this.pressedColor,
    this.hint,
    this.hintColor = const Color(0xFFB9F0C8),
  }) : super(
         repaint: hint == null ? pressed : Listenable.merge([pressed, hint]),
       );

  final int lowPitch;
  final int highPitch;
  final ValueNotifier<Set<int>> pressed;
  final Color pressedColor;

  /// Keys to highlight as "play this next".
  final ValueNotifier<Set<int>>? hint;
  final Color hintColor;

  @override
  void paint(Canvas canvas, Size size) {
    final g = KeyGeometry(lowPitch: lowPitch, highPitch: highPitch, size: size);
    final down = pressed.value;
    final next = hint?.value ?? const <int>{};
    final border = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke;

    for (var p = lowPitch; p <= highPitch; p++) {
      if (KeyGeometry.isBlack(p)) continue;
      final r = g.keyRect(p);
      canvas.drawRect(
        r,
        Paint()
          ..color = down.contains(p)
              ? pressedColor
              : next.contains(p)
              ? hintColor
              : Colors.white,
      );
      canvas.drawRect(r, border);
    }
    for (var p = lowPitch; p <= highPitch; p++) {
      if (!KeyGeometry.isBlack(p)) continue;
      final r = g.keyRect(p);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          r,
          bottomLeft: const Radius.circular(3),
          bottomRight: const Radius.circular(3),
        ),
        Paint()
          ..color = down.contains(p)
              ? pressedColor
              : next.contains(p)
              ? Color.lerp(hintColor, Colors.black, 0.45)!
              : const Color(0xFF1B1B1F),
      );
    }
  }

  @override
  bool shouldRepaint(KeyboardPainter old) =>
      old.lowPitch != lowPitch ||
      old.highPitch != highPitch ||
      old.pressedColor != pressedColor;
}
