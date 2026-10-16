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

/// Which staves to draw; comes from the level's `ui` field.
enum Staves { treble, bass, grand }

/// A short hit effect: rings that grow and fade at a note position.
class HitBurst {
  HitBurst({
    required this.beat,
    required this.pitch,
    required this.leftHand,
    required this.startSec,
    this.whole = false,
  });

  final double beat;
  final int pitch;
  final bool leftHand;
  final double startSec;

  /// Whole notes have a wider head; used to centre the rings on it.
  final bool whole;

  static const durationSec = 0.45;
}

/// Staff renderer. [scrollBeat] is the beat drawn at the anchor x
/// (`lineRatio` × width): in play-along it is the song time and a glowing
/// play bar marks the anchor; in wait mode it is a page offset that slides
/// only when the current note runs off the page, and no bar is drawn.
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
    this.staves = Staves.grand,
    this.bandColor,
    this.badgeColorOf,
    this.badgeTextColor = Colors.white,
    this.showEndCheck = false,
    this.checkColor = const Color(0xFF22C55E),
    this.currentIndex,
    this.currentGlow,
    this.bursts = const [],
    this.burstColor = const Color(0xFF4FC3FF),
    this.clockSec,
    this.beatsPerBar,
    this.dimmed = false,
    this.waitBeamOpacity,
    this.beatPulse,
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
  final Staves staves;

  /// Optional band painted behind the staff lines (e.g. white on a colored stage).
  final Color? bandColor;

  /// When set, finger numbers are drawn in rounded badges of this color.
  final Color? Function(int index)? badgeColorOf;
  final Color badgeTextColor;

  /// Draws a check mark after the last note (wait stage completed).
  final bool showEndCheck;
  final Color checkColor;

  /// Index into [notes] of the note to play next, drawn with [currentGlow].
  final int? Function()? currentIndex;
  final Color? currentGlow;

  final List<HitBurst> bursts;
  final Color burstColor;

  /// Current time in seconds for animating [bursts].
  final double Function()? clockSec;

  /// Draws bar lines every this many beats when set.
  final double? beatsPerBar;

  /// Paused look: band and notation fade.
  final bool dimmed;

  /// Wait stage: opacity 0–1 of the vertical light beam over the note awaited
  /// (fades in when a new note becomes current, as in the reference).
  final double Function()? waitBeamOpacity;

  /// Play-along: 0–1 pulse that peaks on each beat; widens the play bar glow.
  final double Function()? beatPulse;

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

  bool get _hasTreble => staves != Staves.bass;
  bool get _hasBass => staves != Staves.treble;

  /// Vertical layout shared by notes and bursts.
  ({double space, double trebleBottomY, double bassTopY}) _layout(Size size) {
    final single = staves != Staves.grand;
    final space = (size.height / (single ? 11 : 16)).clamp(
      6.0,
      single ? 20.0 : 14.0,
    );
    final trebleBottomY = switch (staves) {
      Staves.treble => size.height * 0.5 + space * 2,
      Staves.bass => -1000.0,
      Staves.grand => size.height * 0.42,
    };
    final bassTopY = staves == Staves.bass
        ? size.height * 0.5 - space * 2
        : trebleBottomY + space * 4;
    return (space: space, trebleBottomY: trebleBottomY, bassTopY: bassTopY);
  }

  /// On a single staff every note sits on that staff, whatever the hand.
  bool _onBass(StaffNote n) => switch (staves) {
    Staves.treble => false,
    Staves.bass => true,
    Staves.grand => n.leftHand,
  };

  double _noteY(
    int pitch,
    bool onBass,
    ({double space, double trebleBottomY, double bassTopY}) l,
  ) {
    final step = diatonicStep(pitch);
    final half = l.space / 2;
    return onBass
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
      ..strokeWidth = math.max(1.2, space * 0.09);
    final staffTop = _hasTreble ? trebleBottomY - space * 4 : bassTopY;
    final staffBottom = _hasBass ? bassTopY + space * 4 : trebleBottomY;

    if (bandColor != null) {
      canvas.drawRect(
        Rect.fromLTRB(
          0,
          staffTop - space * 2.2,
          size.width,
          staffBottom + space * 2.2,
        ),
        Paint()
          ..color = dimmed
              ? Color.lerp(bandColor!, const Color(0xFF8A8A8A), 0.85)!
              : bandColor!,
      );
    }

    // Staff lines.
    for (var i = 0; i < 5; i++) {
      if (_hasTreble) {
        canvas.drawLine(
          Offset(0, trebleBottomY - i * space),
          Offset(size.width, trebleBottomY - i * space),
          ink,
        );
      }
      if (_hasBass) {
        canvas.drawLine(
          Offset(0, bassTopY + i * space),
          Offset(size.width, bassTopY + i * space),
          ink,
        );
      }
    }
    // Clefs: G clef origin on G4 line, F clef origin on F3 line.
    if (_hasTreble) {
      _drawGlyph(
        canvas,
        Smufl.gClef,
        glyphSize,
        Offset(space * 0.8, trebleBottomY - space),
        staff,
      );
    }
    if (_hasBass) {
      _drawGlyph(
        canvas,
        Smufl.fClef,
        glyphSize,
        Offset(space * 0.8, bassTopY + space),
        staff,
      );
    }
    final clefRight = space * 4.2;
    if (staves == Staves.grand) {
      // Brace joining the staves.
      final x0 = space * 0.25,
          top = staffTop,
          bot = staffBottom,
          mid = (top + bot) / 2,
          w = space * 0.9;
      final brace = Path()
        ..moveTo(x0 + w, top)
        ..cubicTo(
          x0,
          top + (mid - top) * 0.15,
          x0 + w,
          mid - (mid - top) * 0.25,
          x0,
          mid,
        )
        ..cubicTo(
          x0 + w,
          mid + (bot - mid) * 0.25,
          x0,
          bot - (bot - mid) * 0.15,
          x0 + w,
          bot,
        );
      canvas.drawPath(
        brace,
        Paint()
          ..color = staff
          ..style = PaintingStyle.stroke
          ..strokeWidth = space * 0.35
          ..strokeCap = StrokeCap.round,
      );
    }
    final bpb = beatsPerBar;
    if (bpb != null && bpb > 0) {
      final now0 = scrollBeat.value;
      final firstBar = ((now0 - anchorX / pixelsPerBeat) / bpb).floor();
      final lastBar = ((now0 + (size.width - anchorX) / pixelsPerBeat) / bpb)
          .ceil();
      for (var b = firstBar; b <= lastBar; b++) {
        if (b <= 0) continue;
        final bx = anchorX + (b * bpb - now0) * pixelsPerBeat - space * 0.8;
        if (bx < clefRight) continue;
        canvas.drawLine(Offset(bx, staffTop), Offset(bx, staffBottom), ink);
      }
    }

    // Play bar with a soft glow trail behind it (play-along only).
    if (showPlayLine) {
      // Spans the whole band (band is staff ± 2.2 spaces).
      final top = staffTop - space * 2.2, bottom = staffBottom + space * 2.2;
      final glowRect = Rect.fromLTRB(
        anchorX - space * 2.6,
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
              playheadColor.withValues(alpha: 0.55),
            ],
          ).createShader(glowRect),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(anchorX - 2.5, top, anchorX + 2.5, bottom),
          const Radius.circular(3),
        ),
        Paint()
          ..color = playheadColor
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4),
      );
    }

    // Waiting beam over the current note (wait stages).
    final beamA = waitBeamOpacity?.call() ?? 0;
    final cur0 = currentIndex?.call();
    if (beamA > 0 && cur0 != null && cur0 < notes.length) {
      final bx =
          anchorX +
          (notes[cur0].beat - scrollBeat.value) * pixelsPerBeat +
          space * 0.6;
      final w = space * 2.4;
      final rect = Rect.fromLTRB(bx - w / 2, 0, bx + w / 2, size.height);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.05 * beamA),
              Colors.white.withValues(alpha: 0.55 * beamA),
              Colors.white.withValues(alpha: 0.05 * beamA),
            ],
          ).createShader(rect)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, space * 0.6),
      );
    }

    // Visible window in beats.
    final now = scrollBeat.value;
    final firstBeat = now - anchorX / pixelsPerBeat - 4;
    final lastBeat = now + (size.width - anchorX) / pixelsPerBeat;
    final current = currentIndex?.call();
    double? lastX;
    for (var i = _lowerBound(firstBeat); i < notes.length; i++) {
      final n = notes[i];
      if (n.beat > lastBeat) break;
      final x = anchorX + (n.beat - now) * pixelsPerBeat;
      lastX = x;
      if (x < clefRight) continue; // behind the clef
      final onBass = _onBass(n);
      final step = diatonicStep(n.pitch);
      final y = _noteY(n.pitch, onBass, l);
      _drawLedgers(
        canvas,
        x,
        y,
        onBass,
        step,
        half,
        space,
        trebleBottomY,
        bassTopY,
        ink,
        headWidth: (n.beats >= 4 ? 1.69 : 1.18) * space,
      );
      final color = colorOf?.call(i) ?? inkColor;
      if (i == current && currentGlow != null) {
        canvas.drawCircle(
          Offset(x + space * (n.beats >= 4 ? 0.845 : 0.59), y),
          space * 1.5,
          Paint()
            ..color = currentGlow!.withValues(alpha: 0.35)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, space * 0.8),
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
      if (_isDotted(n.beats)) {
        // Dot sits in a space: nudge up when the note is on a line.
        final dy = step.isEven ? -half : 0.0;
        canvas.drawCircle(
          Offset(x + space * 1.75, y + dy),
          space * 0.2,
          Paint()..color = color,
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
            ..strokeWidth = math.max(1.2, space * 0.1),
        );
      }
      if (n.finger != null) {
        _drawFinger(
          canvas,
          i,
          n,
          x,
          space,
          staffTop,
          staffBottom,
          onBass,
          color,
        );
      }
    }

    if (showEndCheck && lastX != null) {
      final c = Offset(lastX + space * 4, (staffTop + staffBottom) / 2);
      canvas.drawCircle(c, space * 1.6, Paint()..color = checkColor);
      final path = Path()
        ..moveTo(c.dx - space * 0.7, c.dy)
        ..lineTo(c.dx - space * 0.15, c.dy + space * 0.6)
        ..lineTo(c.dx + space * 0.8, c.dy - space * 0.6);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = space * 0.35
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Hit bursts: three rings that grow and fade.
    final t = clockSec?.call();
    if (t != null) {
      for (final b in bursts) {
        final age = (t - b.startSec) / HitBurst.durationSec;
        if (age < 0 || age > 1) continue;
        final onBass = staves == Staves.grand
            ? b.leftHand
            : staves == Staves.bass;
        final c = Offset(
          anchorX +
              (b.beat - now) * pixelsPerBeat +
              space * (b.whole ? 0.845 : 0.59),
          _noteY(b.pitch, onBass, l),
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

  static bool _isDotted(double beats) =>
      const [0.75, 1.5, 3.0, 6.0].any((d) => (beats - d).abs() < 1e-6);

  void _drawFinger(
    Canvas canvas,
    int i,
    StaffNote n,
    double x,
    double space,
    double staffTop,
    double staffBottom,
    bool onBass,
    Color noteColor,
  ) {
    final badge = badgeColorOf?.call(i);
    final tp = TextPainter(
      text: TextSpan(
        text: '${n.finger}',
        style: TextStyle(
          color: badge == null ? noteColor : badgeTextColor,
          fontSize: space * (badge == null ? 1.3 : 1.15),
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final cx = x + space * 0.6;
    // Badges sit above the treble band, or below the bass band.
    final cy = onBass ? staffBottom + space * 3.6 : staffTop - space * 3.6;
    if (badge != null) {
      // Badge and pointer as one shape, so there is no seam between them.
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: space * 2.2,
          height: space * 2.2,
        ),
        Radius.circular(space * 0.6),
      );
      final tip = onBass ? -1.0 : 1.0;
      final pointer = Path()
        ..moveTo(cx - space * 0.4, cy + tip * space * 0.9)
        ..lineTo(cx + space * 0.4, cy + tip * space * 0.9)
        ..lineTo(cx, cy + tip * space * 1.6)
        ..close();
      final shape = Path.combine(
        PathOperation.union,
        Path()..addRRect(r),
        pointer,
      );
      canvas.drawPath(
        shape.shift(Offset(0, space * 0.15)),
        Paint()..color = Colors.black26,
      );
      canvas.drawPath(shape, Paint()..color = badge);
    }
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
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
    Paint ink, {
    required double headWidth,
  }) {
    // Ledger lines extend past the notehead equally on both sides.
    final left = x - space * 0.45;
    final w = headWidth + space * 0.9;
    if (!bass && step < _trebleBottomStep) {
      for (var s = _trebleBottomStep - 2; s >= step; s -= 2) {
        final ly = trebleBottomY + (_trebleBottomStep - s) * half;
        canvas.drawLine(Offset(left, ly), Offset(left + w, ly), ink);
      }
    }
    if (!bass && step > _trebleBottomStep + 8) {
      for (var s = _trebleBottomStep + 10; s <= step; s += 2) {
        final ly = trebleBottomY - (s - _trebleBottomStep) * half;
        canvas.drawLine(Offset(left, ly), Offset(left + w, ly), ink);
      }
    }
    if (bass && step > _bassTopStep) {
      for (var s = _bassTopStep + 2; s <= step; s += 2) {
        final ly = bassTopY - (s - _bassTopStep) * half;
        canvas.drawLine(Offset(left, ly), Offset(left + w, ly), ink);
      }
    }
    if (bass && step < _bassTopStep - 8) {
      for (var s = _bassTopStep - 10; s >= step; s -= 2) {
        final ly = bassTopY + (_bassTopStep - s) * half;
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
      old.showEndCheck != showEndCheck ||
      old.dimmed != dimmed ||
      old.beatsPerBar != beatsPerBar ||
      old.staves != staves ||
      old.lineRatio != lineRatio ||
      old.pixelsPerBeat != pixelsPerBeat;
}
