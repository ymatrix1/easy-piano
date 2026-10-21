import 'package:flutter/material.dart';

import '../ui/key_geometry.dart';

/// One play-along feedback event to animate (docs/specs/practice-screen.md).
enum FeedbackKind { early, late, wrong, missed }

class FeedbackMark {
  FeedbackMark(this.kind, this.startSec, {this.pitches = const []});

  final FeedbackKind kind;
  final double startSec;

  /// Wrong: the pressed key. Missed: the keys that should have been played.
  final List<int> pitches;

  static const durationSec = 0.6;

  double age(double now) => now - startSec;
}

/// Overlay drawn over the staff at the play bar: an "early"/"late" tag above
/// the bar for off-time hits. Misses show only as red notes (staff painter),
/// like the reference. Lives outside the staff painter on purpose.
class StaffFeedbackPainter extends CustomPainter {
  StaffFeedbackPainter({
    required this.marks,
    required this.lineX,
    required this.clockSec,
    required this.earlyLabel,
    required this.lateLabel,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final List<FeedbackMark> marks;
  final double lineX;
  final double Function() clockSec;
  final String earlyLabel, lateLabel;

  static const cross = Color(0xFFE53935);
  static const tag = Color(0xFFFFB300);

  @override
  void paint(Canvas canvas, Size size) {
    final now = clockSec();
    var tagRow = 0;
    for (final m in marks) {
      final t = (m.age(now) / FeedbackMark.durationSec).clamp(0.0, 1.0);
      final fade = 1 - t;
      switch (m.kind) {
        case FeedbackKind.wrong:
        case FeedbackKind.missed:
          // Reference: the missed note itself turns red; no mark on the staff.
          break;
        case FeedbackKind.early:
        case FeedbackKind.late:
          final text = m.kind == FeedbackKind.early ? earlyLabel : lateLabel;
          final tp = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(
                color: tag.withValues(alpha: fade),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          // Above the staff band (centred in the canvas) and its finger
          // numbers; rises 18 px while fading, stacked if several overlap.
          final y = size.height / 2 - 165 - 22.0 * tagRow - 18 * t;
          tp.paint(canvas, Offset(lineX - tp.width / 2, y.toDouble()));
          tagRow++;
      }
    }
  }

  @override
  bool shouldRepaint(StaffFeedbackPainter old) => true;
}

/// Overlay drawn over the keyboard: wrong keys flash red, missed notes'
/// keys get a red outline. Fades over [FeedbackMark.durationSec].
class KeyFeedbackPainter extends CustomPainter {
  KeyFeedbackPainter({
    required this.marks,
    required this.lowPitch,
    required this.highPitch,
    required this.clockSec,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final List<FeedbackMark> marks;
  final int lowPitch, highPitch;
  final double Function() clockSec;

  @override
  void paint(Canvas canvas, Size size) {
    final geo = KeyGeometry(
      lowPitch: lowPitch,
      highPitch: highPitch,
      size: size,
    );
    final now = clockSec();
    for (final m in marks) {
      if (m.kind != FeedbackKind.wrong && m.kind != FeedbackKind.missed) {
        continue;
      }
      final fade = 1 - (m.age(now) / FeedbackMark.durationSec).clamp(0.0, 1.0);
      for (final p in m.pitches) {
        if (p < lowPitch || p > highPitch) continue;
        final rect = geo.keyRect(p).deflate(2);
        final paint = m.kind == FeedbackKind.wrong
            ? (Paint()
                ..color = StaffFeedbackPainter.cross.withValues(
                  alpha: 0.7 * fade,
                ))
            : (Paint()
                ..color = StaffFeedbackPainter.cross.withValues(alpha: fade)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(KeyFeedbackPainter old) => true;
}
