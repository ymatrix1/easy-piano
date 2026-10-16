import 'package:flutter/material.dart';

import 'key_geometry.dart';

/// On-screen piano keyboard with pressed keys and "play this next" hints.
class KeyboardPainter extends CustomPainter {
  KeyboardPainter({
    required this.lowPitch,
    required this.highPitch,
    required this.pressed,
    required this.pressedColor,
    this.hint,
    this.hintColor = const Color(0xFFB9F0C8),
    this.labelMiddleC = false,
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

  /// Writes a small "C" on middle C, as a landmark for beginners.
  final bool labelMiddleC;

  @override
  void paint(Canvas canvas, Size size) {
    final g = KeyGeometry(lowPitch: lowPitch, highPitch: highPitch, size: size);
    final down = pressed.value;
    final next = hint?.value ?? const <int>{};
    final border = Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.stroke;

    for (var p = lowPitch; p <= highPitch; p++) {
      if (KeyGeometry.isBlack(p)) continue;
      final r = g.keyRect(p).deflate(0.5);
      final fill = down.contains(p)
          ? pressedColor
          : next.contains(p)
          ? hintColor
          : null;
      final rr = RRect.fromRectAndCorners(
        r,
        bottomLeft: const Radius.circular(4),
        bottomRight: const Radius.circular(4),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: fill == null
                ? const [
                    Color(0xFFE9E6EE),
                    Color(0xFFFFFFFF),
                    Color(0xFFF2F0F5),
                  ]
                : [
                    Color.lerp(fill, Colors.white, 0.25)!,
                    fill,
                    Color.lerp(fill, Colors.black, 0.08)!,
                  ],
            stops: const [0, 0.55, 1],
          ).createShader(r),
      );
      canvas.drawRRect(rr, border);
      if (labelMiddleC && p == 60) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'C',
            style: TextStyle(
              color: const Color(0xFF6B6578),
              fontSize: r.width * 0.32,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            r.center.dx - tp.width / 2,
            r.bottom - tp.height - r.width * 0.2,
          ),
        );
      }
    }
    for (var p = lowPitch; p <= highPitch; p++) {
      if (!KeyGeometry.isBlack(p)) continue;
      final r = g.keyRect(p);
      final fill = down.contains(p)
          ? pressedColor
          : next.contains(p)
          ? Color.lerp(hintColor, Colors.black, 0.25)!
          : null;
      final rr = RRect.fromRectAndCorners(
        r,
        bottomLeft: const Radius.circular(3),
        bottomRight: const Radius.circular(3),
      );
      canvas.drawRRect(
        rr.shift(const Offset(1.5, 2)),
        Paint()..color = const Color(0x55000000),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: fill == null
                ? const [Color(0xFF2A2733), Color(0xFF111015)]
                : [fill, Color.lerp(fill, Colors.black, 0.2)!],
          ).createShader(r),
      );
      // Highlight near the front edge, like a lacquered key.
      canvas.drawRect(
        Rect.fromLTWH(
          r.left + r.width * 0.15,
          r.bottom - r.height * 0.12,
          r.width * 0.7,
          r.height * 0.05,
        ),
        Paint()..color = const Color(0x22FFFFFF),
      );
    }
  }

  @override
  bool shouldRepaint(KeyboardPainter old) =>
      old.lowPitch != lowPitch ||
      old.highPitch != highPitch ||
      old.pressedColor != pressedColor ||
      old.labelMiddleC != labelMiddleC;
}
