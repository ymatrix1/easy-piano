import 'package:flutter/material.dart';

import 'key_geometry.dart';

/// On-screen piano keyboard with pressed keys and "play this next" hints.
///
/// Drawn softly on purpose: small gaps between white keys, rounded fronts,
/// shadows instead of outlines, and a felt strip along the top.
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
    final ww = g.whiteWidth;
    final gap = (ww * 0.06).clamp(1.0, 3.0);
    final radius = Radius.circular((ww * 0.18).clamp(3.0, 9.0));

    // Body behind the keys, visible through the gaps.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1C1726),
    );

    for (var p = lowPitch; p <= highPitch; p++) {
      if (KeyGeometry.isBlack(p)) continue;
      final full = g.keyRect(p);
      final isDown = down.contains(p);
      // A pressed key sinks a little.
      final r = Rect.fromLTRB(
        full.left + gap / 2,
        full.top,
        full.right - gap / 2,
        full.bottom - (isDown ? 2 : 4),
      );
      final fill = isDown
          ? pressedColor
          : next.contains(p)
          ? hintColor
          : null;
      final rr = RRect.fromRectAndCorners(
        r,
        bottomLeft: radius,
        bottomRight: radius,
      );
      // Front edge shadow gives depth without an outline.
      canvas.drawRRect(
        rr.shift(const Offset(0, 3)),
        Paint()..color = const Color(0x66000000),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: fill == null
                ? const [
                    Color(0xFFDCD8E3),
                    Color(0xFFFAF9FC),
                    Color(0xFFFFFFFF),
                  ]
                : [
                    Color.lerp(fill, Colors.black, 0.08)!,
                    fill,
                    Color.lerp(fill, Colors.white, 0.2)!,
                  ],
            stops: const [0, 0.35, 1],
          ).createShader(r),
      );
      if (labelMiddleC && p == 60) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'C',
            style: TextStyle(
              color: const Color(0xFF6B6578),
              fontSize: ww * 0.34,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(r.center.dx - tp.width / 2, r.bottom - tp.height - ww * 0.22),
        );
      }
    }

    for (var p = lowPitch; p <= highPitch; p++) {
      if (!KeyGeometry.isBlack(p)) continue;
      final base = g.keyRect(p);
      final isDown = down.contains(p);
      final r = Rect.fromLTRB(
        base.left + base.width * 0.06,
        base.top,
        base.right - base.width * 0.06,
        base.bottom - (isDown ? 0 : 2),
      );
      final fill = isDown
          ? pressedColor
          : next.contains(p)
          ? Color.lerp(hintColor, Colors.black, 0.2)!
          : null;
      final br = Radius.circular((r.width * 0.22).clamp(2.0, 6.0));
      final rr = RRect.fromRectAndCorners(r, bottomLeft: br, bottomRight: br);
      canvas.drawRRect(
        rr.shift(const Offset(2, 3)),
        Paint()
          ..color = const Color(0x77000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: fill == null
                ? const [
                    Color(0xFF16131C),
                    Color(0xFF2E2938),
                    Color(0xFF0E0C12),
                  ]
                : [
                    Color.lerp(fill, Colors.black, 0.25)!,
                    fill,
                    Color.lerp(fill, Colors.black, 0.3)!,
                  ],
            stops: const [0, 0.82, 1],
          ).createShader(r),
      );
      // Bevel highlight on the top face, near the front.
      final face = RRect.fromRectAndCorners(
        Rect.fromLTRB(
          r.left + r.width * 0.16,
          r.top,
          r.right - r.width * 0.16,
          r.bottom - r.height * 0.14,
        ),
        bottomLeft: br,
        bottomRight: br,
      );
      canvas.drawRRect(face, Paint()..color = const Color(0x14FFFFFF));
    }

    // Felt strip along the top edge.
    final felt = Rect.fromLTWH(
      0,
      0,
      size.width,
      (size.height * 0.05).clamp(3.0, 8.0),
    );
    canvas.drawRect(
      felt,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3B1E2E), Color(0x003B1E2E)],
        ).createShader(felt),
    );
  }

  @override
  bool shouldRepaint(KeyboardPainter old) =>
      old.lowPitch != lowPitch ||
      old.highPitch != highPitch ||
      old.pressedColor != pressedColor ||
      old.labelMiddleC != labelMiddleC;
}
