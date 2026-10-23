import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'music_font.dart';
import 'staff_note.dart';

/// SMuFL code points (Leland / Bravura standard).
abstract final class Smufl {
  static const gClef = '';
  static const fClef = '';
  static const noteheadWhole = '';
  static const noteheadHalf = '';
  static const noteheadBlack = '';
  static const accidentalSharp = '';
  static const restWhole = '';
  static const restHalf = '';
  static const restQuarter = '';
  static const rest8th = '';
  static const rest16th = '';

  // Flags for 8th and 16th notes
  static const flag8thUp = '\uE240';
  static const flag8thDown = '\uE241';
  static const flag16thUp = '\uE242';
  static const flag16thDown = '\uE243';

  // Time signatures
  static const timeSig0 = '';
  static const timeSig1 = '';
  static const timeSig2 = '';
  static const timeSig3 = '';
  static const timeSig4 = '';
  static const timeSig5 = '';
  static const timeSig6 = '';
  static const timeSig7 = '';
  static const timeSig8 = '';
  static const timeSig9 = '';

  static String? digitGlyph(int digit) => switch (digit) {
    0 => timeSig0,
    1 => timeSig1,
    2 => timeSig2,
    3 => timeSig3,
    4 => timeSig4,
    5 => timeSig5,
    6 => timeSig6,
    7 => timeSig7,
    8 => timeSig8,
    9 => timeSig9,
    _ => null,
  };
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
    this.introStartSec,
    this.beatPulse,
    Listenable? repaintAlso,
  }) : scrollBeat = playheadBeat,
       super(
         repaint: Listenable.merge([
           playheadBeat,
           musicFontReady,
           ?repaintAlso,
         ]),
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

  /// [clockSec] time the stage opened. Visible notes then rise from below
  /// the staff, staggered, with an overshoot ease and a fade in (reference
  /// stage intro). Null: no intro.
  final double? introStartSec;

  /// Intro animation for the [k]th of [n] visible notes, [elapsed] seconds
  /// after the stage opened: delay k/(2n), duration min(1-(n-1)/(2n), 0.5),
  /// swingOut(2) ease. Returns rise (1 = fully below, 0 = in place; may go
  /// negative on overshoot) and alpha.
  static ({double rise, double alpha}) introAt(double elapsed, int k, int n) {
    if (n <= 0) return (rise: 0, alpha: 1);
    final step = 1 / (2 * n);
    final dur = math.min(1 - (n - 1) * step, 0.5);
    final p = ((elapsed - k * step) / dur).clamp(0.0, 1.0);
    const s = 2.0;
    final q = p - 1;
    final eased = ((s + 1) * q + s) * q * q + 1;
    return (rise: 1 - eased, alpha: p);
  }

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
            fontFamily: 'Leland',
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
  static int lowerBound(List<StaffNote> list, double beat) {
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid].beat < beat) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  int _lowerBound(double beat) => lowerBound(notes, beat);

  /// Horizontal system layout in staff spaces. A grand staff starts with a
  /// brace just left of the system line; a single staff has no brace. The
  /// clef sits one space after the line in both.
  static ({double systemX, double clefX, double clefRight}) systemLayout(
    Staves staves,
    double space, {
    double? beatsPerBar,
  }) {
    final grand = staves == Staves.grand;
    final systemX = space * (grand ? 2.2 : 0.6);
    final clefX = systemX + space * 1.0;
    // Clef glyphs are ~2.7 spaces wide.
    var right = clefX + space * 3.4;
    if (beatsPerBar != null && beatsPerBar > 0) {
      // Time signature digits sit at clefX + 3.8 spaces, width ~1.8 spaces + clearance.
      right = clefX + space * 6.0;
    }
    return (systemX: systemX, clefX: clefX, clefRight: right);
  }

  /// Horizontal edge-fade mask for everything that scrolls (noteheads,
  /// stems, ledgers, dots, finger labels, hit bursts): fully transparent at
  /// and left of [clear] (the clefs' right edge), linear up to fully opaque
  /// at [full], a little before the anchor so the current note is never
  /// dimmed.
  static ({double clear, double full}) edgeFade(
    double clefRight,
    double anchorX,
    double space,
  ) {
    final full = math.max(clefRight + 1.0, anchorX - space * 0.6);
    return (clear: clefRight, full: full);
  }

  /// Computes the horizontal position of a bar line at [barBeat].
  ///
  /// By default the bar line sits `space * 0.8` before the start of the bar.
  /// If a note immediately precedes the bar line with a tight gap (e.g. an
  /// eighth note), the bar line is balanced between the preceding note's right
  /// edge and the following note's left edge so it never collides with stems.
  static double barLineX({
    required double barBeat,
    required double nowBeat,
    required double anchorX,
    required double pixelsPerBeat,
    required double space,
    List<StaffNote>? notes,
  }) {
    final barX = anchorX + (barBeat - nowBeat) * pixelsPerBeat;
    if (notes == null || notes.isEmpty) return barX - space * 0.8;

    final idx = lowerBound(notes, barBeat);

    // Rightmost visual edge of notes preceding barBeat (within 2 beats).
    double? prevRight;
    for (var i = idx - 1; i >= 0; i--) {
      final n = notes[i];
      if (barBeat - n.beat > 2.0) break;
      if (n.isSpacer) continue;
      final nx = anchorX + (n.beat - nowBeat) * pixelsPerBeat;
      final width = n.isRest
          ? space * 1.0
          : (_isDotted(n.beats)
                ? space * 1.95
                : (n.beats >= 4 ? space * 1.5 : space * 1.3));
      final right = nx + width;
      if (prevRight == null || right > prevRight) {
        prevRight = right;
      }
    }

    // Leftmost visual edge of notes at or just after barBeat.
    double? nextLeft;
    for (var i = idx; i < notes.length; i++) {
      final n = notes[i];
      if (n.beat - barBeat > 0.05) break;
      if (n.isSpacer) continue;
      final nx = anchorX + (n.beat - nowBeat) * pixelsPerBeat;
      final left = _isSharp[n.pitch % 12] ? nx - space * 1.3 : nx;
      if (nextLeft == null || left < nextLeft) {
        nextLeft = left;
      }
    }

    final rightBoundary = nextLeft ?? barX;
    final nominalBx = rightBoundary - space * 0.8;

    if (prevRight != null) {
      if (rightBoundary > prevRight) {
        final centered = (prevRight + rightBoundary) / 2;
        if (nominalBx < centered) {
          return centered;
        }
      } else {
        return (prevRight + rightBoundary) / 2;
      }
    }

    return nominalBx;
  }

  /// Spacing between notes and accidentals: ensures accidentals don't collide
  /// with preceding noteheads/stems on tight rhythms (e.g. 8th notes).
  static double noteX({
    required int index,
    required List<StaffNote> notes,
    required double anchorX,
    required double nowBeat,
    required double pixelsPerBeat,
    required double space,
  }) {
    final n = notes[index];
    final nominalX = anchorX + (n.beat - nowBeat) * pixelsPerBeat;
    if (!_isSharp[n.pitch % 12]) return nominalX;

    // Find preceding note on the same staff/voice region within 2 beats.
    // Notes with the exact same beat (chords) are not preceding horizontal notes.
    final onBass = n.leftHand;
    double? prevRight;
    for (var i = index - 1; i >= 0; i--) {
      final prev = notes[i];
      if ((prev.beat - n.beat).abs() < 1e-6) continue;
      if (n.beat - prev.beat > 2.0) break;
      if (prev.isSpacer || prev.leftHand != onBass) continue;
      final px = anchorX + (prev.beat - nowBeat) * pixelsPerBeat;
      final pWidth = prev.isRest
          ? space * 1.0
          : (_isDotted(prev.beats)
                ? space * 1.95
                : (prev.beats >= 4 ? space * 1.5 : space * 1.3));
      final pr = px + pWidth;
      if (prevRight == null || pr > prevRight) {
        prevRight = pr;
      }
    }

    if (prevRight != null) {
      // Accidental is drawn at x - space * 1.3. Keep at least space * 0.4 clearance.
      final minX = prevRight + space * 1.7;
      if (nominalX < minX) {
        return minX;
      }
    }

    return nominalX;
  }

  /// Grand staff: spaces between the treble bottom line and the bass top
  /// line (reference: about 2; 3 leaves room for middle-C ledgers).
  static const staffGap = 3.0;

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
        : trebleBottomY + space * staffGap;
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
    final bpb = beatsPerBar;
    final sys = systemLayout(staves, space, beatsPerBar: bpb);

    // Band, staff lines, clefs, time signature and brace.
    void paintBackground() {
      if (bandColor != null) {
        final band = Paint()
          ..color = dimmed
              ? Color.lerp(bandColor!, const Color(0xFF8A8A8A), 0.85)!
              : bandColor!;
        final frame = Paint()
          ..color = staff
          ..style = PaintingStyle.stroke
          ..strokeWidth = ink.strokeWidth * 2;
        final inset = frame.strokeWidth / 2;

        if (_hasTreble) {
          final rect = Rect.fromLTRB(
            sys.systemX,
            trebleBottomY - space * 4,
            size.width,
            trebleBottomY,
          );
          canvas.drawRect(rect, band);
          canvas.drawRect(
            Rect.fromLTRB(
              sys.systemX,
              rect.top,
              size.width - inset,
              rect.bottom,
            ),
            frame,
          );
        }
        if (_hasBass) {
          final rect = Rect.fromLTRB(
            sys.systemX,
            bassTopY,
            size.width,
            bassTopY + space * 4,
          );
          canvas.drawRect(rect, band);
          canvas.drawRect(
            Rect.fromLTRB(
              sys.systemX,
              rect.top,
              size.width - inset,
              rect.bottom,
            ),
            frame,
          );
        }
      }

      // Staff lines.
      for (var i = 0; i < 5; i++) {
        if (_hasTreble) {
          canvas.drawLine(
            Offset(sys.systemX, trebleBottomY - i * space),
            Offset(size.width, trebleBottomY - i * space),
            ink,
          );
        }
        if (_hasBass) {
          canvas.drawLine(
            Offset(sys.systemX, bassTopY + i * space),
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
          Offset(sys.clefX, trebleBottomY - space),
          staff,
        );
      }
      if (_hasBass) {
        _drawGlyph(
          canvas,
          Smufl.fClef,
          glyphSize,
          Offset(sys.clefX, bassTopY + space),
          staff,
        );
      }

      // Time signature: numerator on upper 2 spaces, denominator on lower 2 spaces.
      if (bpb != null && bpb > 0) {
        final numDigit = bpb.round();
        final numGlyph = Smufl.digitGlyph(numDigit);
        final denGlyph = Smufl.digitGlyph(
          4,
        ); // Default quarter note denominator
        final tsX = sys.clefX + space * 3.8;
        if (numGlyph != null && denGlyph != null) {
          if (_hasTreble) {
            _drawGlyph(
              canvas,
              numGlyph,
              glyphSize,
              Offset(tsX, trebleBottomY - space * 3),
              staff,
            );
            _drawGlyph(
              canvas,
              denGlyph,
              glyphSize,
              Offset(tsX, trebleBottomY - space * 1),
              staff,
            );
          }
          if (_hasBass) {
            _drawGlyph(
              canvas,
              numGlyph,
              glyphSize,
              Offset(tsX, bassTopY + space * 1),
              staff,
            );
            _drawGlyph(
              canvas,
              denGlyph,
              glyphSize,
              Offset(tsX, bassTopY + space * 3),
              staff,
            );
          }
        }
      }

      if (staves == Staves.grand) {
        // System line joining treble and bass
        canvas.drawLine(
          Offset(sys.systemX, staffTop),
          Offset(sys.systemX, staffBottom),
          ink,
        );

        // Brace left of the system line.
        final x0 = sys.systemX - space * 1.9,
            top = staffTop,
            bot = staffBottom,
            mid = (top + bot) / 2,
            w = space * 1.4;
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
            ..color = staff.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = space * 0.45
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    paintBackground();
    final clefRight = sys.clefRight;
    if (bpb != null && bpb > 0) {
      final now0 = scrollBeat.value;
      final firstBar = ((now0 - anchorX / pixelsPerBeat) / bpb).floor();
      final lastBar = ((now0 + (size.width - anchorX) / pixelsPerBeat) / bpb)
          .ceil();
      for (var b = firstBar; b <= lastBar; b++) {
        if (b <= 0) continue;
        final bx = barLineX(
          barBeat: b * bpb.toDouble(),
          nowBeat: now0,
          anchorX: anchorX,
          pixelsPerBeat: pixelsPerBeat,
          space: space,
          notes: notes,
        );
        if (bx < clefRight) continue;
        canvas.drawLine(Offset(bx, staffTop), Offset(bx, staffBottom), ink);
      }
    }

    void paintPlayBar() {
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
    }

    paintPlayBar();

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
    final introT = introStartSec == null || clockSec == null
        ? null
        : clockSec!() - introStartSec!;
    final introOn = introT != null && introT < 1.0;
    final first = _lowerBound(firstBeat);
    // All scrolling elements go through one layer that is masked at the end.
    final fade = edgeFade(clefRight, anchorX, space);
    canvas.saveLayer(Offset.zero & size, Paint());
    var introN = 0;
    if (introOn) {
      for (var i = first; i < notes.length && notes[i].beat <= lastBeat; i++) {
        introN++;
      }
    }
    final drawnUnisons = <(double, int, bool)>{};
    for (var i = first; i < notes.length; i++) {
      final n = notes[i];
      if (n.beat > lastBeat) break;
      final x = noteX(
        index: i,
        notes: notes,
        anchorX: anchorX,
        nowBeat: now,
        pixelsPerBeat: pixelsPerBeat,
        space: space,
      );
      lastX = x;
      if (x + space * 2 < 0) continue; // off screen; the cover hides the rest
      if (n.isSpacer) continue;
      final intro = introOn ? introAt(introT, i - first, introN) : null;
      if (intro != null) {
        if (intro.alpha <= 0) continue;
        canvas.saveLayer(
          null,
          Paint()..color = Color.fromRGBO(0, 0, 0, intro.alpha),
        );
        canvas.translate(0, intro.rise * size.height);
      }
      final onBass = _onBass(n);
      final color = colorOf?.call(i) ?? inkColor;
      if (n.isRest) {
        final restY =
            (onBass ? bassTopY + 2 * space : trebleBottomY - 2 * space) +
            (n.voice == 2 ? (onBass ? -2 : 2) * space : 0.0);
        final restGlyph = n.beats >= 4
            ? Smufl.restWhole
            : n.beats >= 2
            ? Smufl.restHalf
            : n.beats >= 1
            ? Smufl.restQuarter
            : n.beats >= 0.5
            ? Smufl.rest8th
            : Smufl.rest16th;
        _drawGlyph(canvas, restGlyph, glyphSize, Offset(x, restY), color);
        if (intro != null) canvas.restore();
        continue;
      }

      final step = diatonicStep(n.pitch);
      final y = _noteY(n.pitch, onBass, l);
      final noteKey = (n.beat, n.pitch, onBass);
      final isDuplicate = drawnUnisons.contains(noteKey);
      drawnUnisons.add(noteKey);

      if (!isDuplicate) {
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
          headWidth: (n.beats >= 4 ? 1.5 : 1.3) * space,
        );
        if (i == current && currentGlow != null) {
          canvas.drawCircle(
            Offset(x + space * (n.beats >= 4 ? 0.75 : 0.65), y),
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
            Offset(x - space * 1.3, y),
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
      }

      if (n.beats < 4) {
        final strokePaint = Paint()
          ..color = color
          ..strokeWidth = math.max(1.2, space * 0.1);
        final sxUp = x + space * 1.3 - strokePaint.strokeWidth / 2;
        final sxDown = x + strokePaint.strokeWidth / 2;

        // Check if there are other chord notes on the same beat and hand
        var isLowestOfChord = true;
        var isHighestOfChord = true;
        var hasOtherChordNote = false;
        for (var k = 0; k < notes.length; k++) {
          if (k == i) continue;
          final other = notes[k];
          if ((other.beat - n.beat).abs() < 1e-6 &&
              other.leftHand == n.leftHand &&
              !other.isSpacer &&
              !other.isRest) {
            hasOtherChordNote = true;
            if (other.pitch < n.pitch) isLowestOfChord = false;
            if (other.pitch > n.pitch) isHighestOfChord = false;
          }
        }

        if (hasOtherChordNote) {
          // In a chord: draw connecting stem between notes, and extend the main stem
          final stemDown = n.stemDown;
          if (stemDown) {
            // Downward stem extends from the lowest note downward
            if (isLowestOfChord) {
              final tipY = y + space * 3.5;
              canvas.drawLine(
                Offset(sxDown, y),
                Offset(sxDown, tipY),
                strokePaint,
              );
              if (n.beats <= 0.75) {
                final flag = n.beats <= 0.375
                    ? Smufl.flag16thDown
                    : Smufl.flag8thDown;
                _drawGlyph(
                  canvas,
                  flag,
                  glyphSize,
                  Offset(sxDown, tipY),
                  color,
                );
              }
            }
          } else {
            // Upward stem extends from the highest note upward
            if (isHighestOfChord) {
              final tipY = y - space * 3.5;
              canvas.drawLine(Offset(sxUp, y), Offset(sxUp, tipY), strokePaint);
              if (n.beats <= 0.75) {
                final flag = n.beats <= 0.375
                    ? Smufl.flag16thUp
                    : Smufl.flag8thUp;
                _drawGlyph(canvas, flag, glyphSize, Offset(sxUp, tipY), color);
              }
            }
          }
          // Also connect this note to adjacent chord notes if needed
          for (var k = i + 1; k < notes.length; k++) {
            final other = notes[k];
            if ((other.beat - n.beat).abs() < 1e-6 &&
                other.leftHand == n.leftHand &&
                !other.isSpacer &&
                !other.isRest) {
              final otherY = _noteY(other.pitch, onBass, l);
              final connectX = stemDown ? sxDown : sxUp;
              canvas.drawLine(
                Offset(connectX, y),
                Offset(connectX, otherY),
                strokePaint,
              );
            }
          }
        } else if (n.twoStems || isDuplicate) {
          final tipUpY = y - space * 3.5;
          final tipDownY = y + space * 3.5;
          canvas.drawLine(Offset(sxUp, y), Offset(sxUp, tipUpY), strokePaint);
          canvas.drawLine(
            Offset(sxDown, y),
            Offset(sxDown, tipDownY),
            strokePaint,
          );
          if (n.beats <= 0.75) {
            final flagUp = n.beats <= 0.375
                ? Smufl.flag16thUp
                : Smufl.flag8thUp;
            final flagDown = n.beats <= 0.375
                ? Smufl.flag16thDown
                : Smufl.flag8thDown;
            _drawGlyph(canvas, flagUp, glyphSize, Offset(sxUp, tipUpY), color);
            _drawGlyph(
              canvas,
              flagDown,
              glyphSize,
              Offset(sxDown, tipDownY),
              color,
            );
          }
        } else if (n.stemDown) {
          final tipY = y + space * 3.5;
          canvas.drawLine(Offset(sxDown, y), Offset(sxDown, tipY), strokePaint);
          if (n.beats <= 0.75) {
            final flag = n.beats <= 0.375
                ? Smufl.flag16thDown
                : Smufl.flag8thDown;
            _drawGlyph(canvas, flag, glyphSize, Offset(sxDown, tipY), color);
          }
        } else {
          final tipY = y - space * 3.5;
          canvas.drawLine(Offset(sxUp, y), Offset(sxUp, tipY), strokePaint);
          if (n.beats <= 0.75) {
            final flag = n.beats <= 0.375 ? Smufl.flag16thUp : Smufl.flag8thUp;
            _drawGlyph(canvas, flag, glyphSize, Offset(sxUp, tipY), color);
          }
        }
      }
      if (n.finger != null && _shouldDrawFinger(i)) {
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
      if (intro != null) canvas.restore();
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

    // Mask the layer: alpha 0 up to the clefs' right edge, ramping to 1.
    final maskRect = Offset.zero & size;
    canvas.drawRect(
      maskRect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = LinearGradient(
          colors: const [
            Color(0x00000000),
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
          ],
          stops: [0, fade.clear / size.width, fade.full / size.width, 1],
        ).createShader(maskRect),
    );
    canvas.restore();
  }

  static bool _isDotted(double beats) =>
      const [0.75, 1.5, 3.0, 6.0].any((d) => (beats - d).abs() < 1e-6);

  /// Decides if fingering text should be rendered for note at [index].
  /// Shows fingering if it has an active badge, if it's the first note for that hand,
  /// if the finger changed from the previous note played by the same hand,
  /// or if there is a hand position leap / large rest gap.
  /// For chords (simultaneous notes on the same beat), fingerings are only shown
  /// on the top note (or lowest if bass) to avoid overlapping text collisions.
  bool _shouldDrawFinger(int index) {
    final n = notes[index];
    if (n.finger == null) return false;
    if (badgeColorOf?.call(index) != null) return true;

    // Check if this note is part of a chord on the same hand.
    // If so, only show fingering on the topmost note of the chord to prevent overlaps.
    for (var k = 0; k < notes.length; k++) {
      if (k == index) continue;
      final other = notes[k];
      if ((other.beat - n.beat).abs() < 1e-6 &&
          other.leftHand == n.leftHand &&
          !other.isSpacer &&
          !other.isRest) {
        if (other.pitch > n.pitch) {
          // A higher note exists in this chord; don't draw on this lower note
          return false;
        }
      }
    }

    // Look for previous playable note for the same hand
    StaffNote? prev;
    for (var k = index - 1; k >= 0; k--) {
      final cand = notes[k];
      if ((cand.beat - n.beat).abs() < 1e-6) continue;
      if (!cand.isSpacer && !cand.isRest && cand.leftHand == n.leftHand) {
        prev = cand;
        break;
      }
    }

    if (prev == null) return true; // First note of this hand
    if (prev.finger != n.finger) return true; // Finger changed
    if ((n.pitch - prev.pitch).abs() >= 5) return true; // Hand position shifted
    if (n.beat - prev.beat >= 4.0) return true; // New phrase after gap
    return false;
  }

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
      old.introStartSec != introStartSec ||
      old.pixelsPerBeat != pixelsPerBeat;
}
