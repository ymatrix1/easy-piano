import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'staff_note.dart';

/// SMuFL code points (Bravura).
abstract final class Smufl {
  static const gClef = '';
  static const fClef = '';
  static const noteheadWhole = '';
  static const noteheadHalf = '';
  static const noteheadBlack = '';
  static const accidentalSharp = '';
}

/// A short hit effect: rings that grow and fade at a note position.
class HitBurst {
  HitBurst({
    required this.beat,
    required this.pitch,
    required this.leftHand,
    required this.startSec,
  });

  final double beat;
  final int pitch;
  final bool leftHand;
  final double startSec;

  static const durationSec = 0.45;
}

/// Grand staff. [scrollBeat] is the beat drawn at the anchor x
/// (`lineRatio` × width): in play-along it is the song time and a glowing
/// play line marks the anchor; in wait mode it is a page offset that slides
/// only when the current note runs off the page, and no line is drawn.
/// Only notes inside the visible beat window are laid out and painted.
class StaffPainter extends CustomPainter {
  StaffPainter({
    required this.notes,
    required ValueNotifier<double> playheadBeat,
    required this.inkColor,
    required this.playheadColor,
    this.pixelsPerBeat = 90,
    this.colorOf,
    this.lineRatio = 0.22,
    this.showPlayLine = true,
    this.staffColor,
    this.currentIndex,
    this.currentGlow,
    this.bursts = const [],
    this.burstColor = const Color(0xFF4FC3FF),
    this.clockSec,
    Listenable? repaintAlso,
  }) : scrollBeat = playheadBeat,
       super(
         repaint: repaintAlso == null
             ? playheadBeat
             : Listenable.merge([playheadBeat, repaintAlso]),
       );

  final List<StaffNote> notes;
  final ValueNotifier<double> scrollBeat;
  final Color inkColor;
  final Color playheadColor;
  final double pixelsPerBeat;

  /// Optional per-note color (by index into [notes]), e.g. hit/miss feedback.
  final Color Function(int index)? colorOf;

  /// Anchor x as a fraction of the width.
  final double lineRatio;
  final bool showPlayLine;

  /// Staff lines and clefs; defaults to [inkColor].
  final Color? staffColor;

  /// Index into [notes] of the note to play next, drawn with [currentGlow].
  final int? Function()? currentIndex;
  final Color? currentGlow;

  final List<HitBurst> bursts;
  final Color burstColor;

  /// Current time in seconds for animating [bursts].
  final double Function()? clockSec;

  // Diatonic step within an octave for each pitch class (sharp spelling).
  static const _stepOf = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6];
  static const _isSharp = [
    false,
    true,
    false,
    true,
    false,
    false,
    true,
    false,
    true,
    false,
    true,
    false,
  ];

  static int diatonicStep(int pitch) =>
      (pitch ~/ 12 - 1) * 7 + _stepOf[pitch % 12];

  // Bottom line of treble staff is E4; top line of bass staff is A3.
  static final _trebleBottomStep = diatonicStep(64);
  static final _bassTopStep = diatonicStep(57);

  final _glyphCache = <String, TextPainter>{};

  TextPainter _glyph(String g, double size, [Color? color]) {
    final c = color ?? inkColor;
    return _glyphCache.putIfAbsent('$g@$size@${c.toARGB32()}', () {
      return TextPainter(
        text: TextSpan(
          text: g,
          style: TextStyle(
            fontFamily: 'Bravura',
            fontSize: size,
            color: c,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  /// Index of the first note with beat >= [beat] (notes sorted by beat).
  int _lowerBound(double beat) {
    var lo = 0, hi = notes.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (notes[mid].beat < beat) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Vertical layout shared by notes and bursts.
  ({double space, double trebleBottomY, double bassTopY}) _layout(Size size) {
    final space = (size.height / 16).clamp(6.0, 14.0);
    final trebleBottomY = size.height * 0.42;
    return (
      space: space,
      trebleBottomY: trebleBottomY,
      bassTopY: trebleBottomY + space * 4,
    );
  }

  double _noteY(
    int pitch,
    bool leftHand,
    ({double space, double trebleBottomY, double bassTopY}) l,
  ) {
    final step = diatonicStep(pitch);
    final half = l.space / 2;
    return leftHand
        ? l.bassTopY + (_bassTopStep - step) * half
        : l.trebleBottomY - (step - _trebleBottomStep) * half;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final l = _layout(size);
    final space = l.space, half = space / 2;
    final trebleBottomY = l.trebleBottomY, bassTopY = l.bassTopY;
    final glyphSize = space * 4; // SMuFL: 1 em = 4 staff spaces
    final anchorX = size.width * lineRatio;
    final staff = staffColor ?? inkColor;
    final ink = Paint()
      ..color = staff
      ..strokeWidth = 1.2;

    // Staff lines.
    for (var i = 0; i < 5; i++) {
      final ty = trebleBottomY - i * space;
      final by = bassTopY + i * space;
      canvas.drawLine(Offset(0, ty), Offset(size.width, ty), ink);
      canvas.drawLine(Offset(0, by), Offset(size.width, by), ink);
    }
    // Clefs: G clef origin on G4 line, F clef origin on F3 line.
    _drawGlyph(
      canvas,
      Smufl.gClef,
      glyphSize,
      Offset(8, trebleBottomY - space),
      staff,
    );
    _drawGlyph(
      canvas,
      Smufl.fClef,
      glyphSize,
      Offset(8, bassTopY + space),
      staff,
    );

    // Play line with a soft glow (play-along only).
    if (showPlayLine) {
      final top = trebleBottomY - space * 6, bottom = bassTopY + space * 6;
      final glowRect = Rect.fromLTRB(
        anchorX - space * 2.2,
        top,
        anchorX,
        bottom,
      );
      canvas.drawRect(
        glowRect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              playheadColor.withValues(alpha: 0),
              playheadColor.withValues(alpha: 0.35),
            ],
          ).createShader(glowRect),
      );
      canvas.drawLine(
        Offset(anchorX, top),
        Offset(anchorX, bottom),
        Paint()
          ..color = playheadColor
          ..strokeWidth = 3
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3),
      );
    }

    // Visible window in beats.
    final now = scrollBeat.value;
    final firstBeat = now - anchorX / pixelsPerBeat - 4;
    final lastBeat = now + (size.width - anchorX) / pixelsPerBeat;
    final current = currentIndex?.call();
    for (var i = _lowerBound(firstBeat); i < notes.length; i++) {
      final n = notes[i];
      if (n.beat > lastBeat) break;
      final x = anchorX + (n.beat - now) * pixelsPerBeat;
      if (x < 60) continue; // behind the clefs
      final step = diatonicStep(n.pitch);
      final y = _noteY(n.pitch, n.leftHand, l);
      _drawLedgers(
        canvas,
        x,
        y,
        n.leftHand,
        step,
        half,
        space,
        trebleBottomY,
        bassTopY,
        ink,
      );
      final color = colorOf?.call(i) ?? inkColor;
      if (i == current && currentGlow != null) {
        canvas.drawCircle(
          Offset(x + space * 0.6, y),
          space * 1.6,
          Paint()
            ..color = currentGlow!.withValues(alpha: 0.45)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, space * 0.9),
        );
      }
      final head = n.beats >= 4
          ? Smufl.noteheadWhole
          : n.beats >= 2
          ? Smufl.noteheadHalf
          : Smufl.noteheadBlack;
      _drawGlyph(canvas, head, glyphSize, Offset(x, y), color);
      if (_isSharp[n.pitch % 12]) {
        _drawGlyph(
          canvas,
          Smufl.accidentalSharp,
          glyphSize,
          Offset(x - space * 1.4, y),
          color,
        );
      }
      if (n.beats < 4) {
        // Stem up from the right side of the notehead (1.18 spaces wide in Bravura).
        final sx = x + space * 1.18 - 0.6;
        canvas.drawLine(
          Offset(sx, y),
          Offset(sx, y - space * 3.5),
          Paint()
            ..color = color
            ..strokeWidth = 1.2,
        );
      }
      if (n.finger != null) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${n.finger}',
            style: TextStyle(
              color: color,
              fontSize: space * 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final top = n.leftHand
            ? bassTopY + space * 5
            : trebleBottomY - space * 6.2;
        tp.paint(canvas, Offset(x + space * 0.1, top));
      }
    }

    // Hit bursts: three rings that grow and fade.
    final t = clockSec?.call();
    if (t != null) {
      for (final b in bursts) {
        final age = (t - b.startSec) / HitBurst.durationSec;
        if (age < 0 || age > 1) continue;
        final c = Offset(
          anchorX + (b.beat - now) * pixelsPerBeat + space * 0.6,
          _noteY(b.pitch, b.leftHand, l),
        );
        for (var k = 0; k < 3; k++) {
          final a = (age - k * 0.12).clamp(0.0, 1.0);
          if (a <= 0) continue;
          canvas.drawCircle(
            c,
            space * (0.8 + a * 2.4),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = space * 0.35 * (1 - a)
              ..color = burstColor.withValues(alpha: math.max(0, 0.9 * (1 - a)))
              ..maskFilter = MaskFilter.blur(BlurStyle.solid, space * 0.3),
          );
        }
      }
    }
  }

  void _drawLedgers(
    Canvas canvas,
    double x,
    double y,
    bool bass,
    int step,
    double half,
    double space,
    double trebleBottomY,
    double bassTopY,
    Paint ink,
  ) {
    final w = space * 1.6;
    final left = x - space * 0.2;
    if (!bass && step < _trebleBottomStep) {
      for (var s = _trebleBottomStep - 2; s >= step; s -= 2) {
        final ly = trebleBottomY + (_trebleBottomStep - s) * half;
        canvas.drawLine(Offset(left, ly), Offset(left + w, ly), ink);
      }
    }
    if (bass && step > _bassTopStep) {
      for (var s = _bassTopStep + 2; s <= step; s += 2) {
        final ly = bassTopY - (s - _bassTopStep) * half;
        canvas.drawLine(Offset(left, ly), Offset(left + w, ly), ink);
      }
    }
  }

  /// Draws a SMuFL glyph with its baseline origin at [origin].
  void _drawGlyph(
    Canvas canvas,
    String g,
    double size,
    Offset origin, [
    Color? color,
  ]) {
    final tp = _glyph(g, size, color);
    final baseline = tp.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    tp.paint(canvas, Offset(origin.dx, origin.dy - baseline));
  }

  @override
  bool shouldRepaint(StaffPainter old) =>
      old.notes != notes ||
      old.colorOf != colorOf ||
      old.inkColor != inkColor ||
      old.showPlayLine != showPlayLine ||
      old.lineRatio != lineRatio ||
      old.pixelsPerBeat != pixelsPerBeat;
}
