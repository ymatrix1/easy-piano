import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'beam_layout.dart';
import 'chord_layout.dart';
import 'engraving_decorations.dart';
import 'key_signature.dart';
import 'music_font.dart';
import 'smufl.dart';
import 'staff_note.dart';
import 'stem_layout.dart';
import 'tuplet_layout.dart';

export 'beam_layout.dart';
export 'chord_layout.dart';
export 'engraving_decorations.dart';
export 'key_signature.dart';
export 'smufl.dart';
export 'stem_layout.dart';
export 'tuplet_layout.dart';

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
    this.endBeat,
    this.keyFifths = 0,
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

  /// Beat where the piece ends. When set, a final barline (thin line plus
  /// thick line, MuseScore end barline) is drawn there instead of a regular
  /// bar line.
  final double? endBeat;

  /// Key signature in fifths (positive = sharps, negative = flats, 0 = C maj).
  final int keyFifths;

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
    int keyFifths = 0,
  }) {
    final grand = staves == Staves.grand;
    final systemX = space * (grand ? 2.2 : 0.6);
    final clefX = systemX + space * 1.0;
    // Clef glyphs are ~2.7 spaces wide.
    var right = clefX + space * 3.4;
    if (keyFifths != 0) {
      right += KeySignatureLayout.width(keyFifths, space);
    }
    if (beatsPerBar != null && beatsPerBar > 0) {
      // Time signature digits sit after clef/keysig.
      right = keyFifths != 0 ? right + space * 2.6 : clefX + space * 6.0;
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
    Map<int, double>? xCache,
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
      final nx = xCache?[i] ?? (anchorX + (n.beat - nowBeat) * pixelsPerBeat);
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
      final nx = xCache?[i] ?? (anchorX + (n.beat - nowBeat) * pixelsPerBeat);
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
    Map<int, double>? xCache,
    double? beatsPerBar,
  }) {
    if (xCache != null && xCache.containsKey(index)) return xCache[index]!;
    final n = notes[index];
    final nominalX = anchorX + (n.beat - nowBeat) * pixelsPerBeat;

    // Find preceding note on the same staff/voice region within 2 beats.
    // Notes with the exact same beat (chords) are not preceding horizontal notes.
    final onBass = n.leftHand;
    double? prevRight;
    StaffNote? prevNote;
    for (var i = index - 1; i >= 0; i--) {
      final prev = notes[i];
      if ((prev.beat - n.beat).abs() < 1e-6) continue;
      if (n.beat - prev.beat > 2.0) break;
      if (prev.isSpacer || prev.leftHand != onBass) continue;
      final px = xCache != null && xCache.containsKey(i)
          ? xCache[i]!
          : noteX(
              index: i,
              notes: notes,
              anchorX: anchorX,
              nowBeat: nowBeat,
              pixelsPerBeat: pixelsPerBeat,
              space: space,
              xCache: xCache,
              beatsPerBar: beatsPerBar,
            );
      final pWidth = prev.isRest
          ? space * 1.0
          : (_isDotted(prev.beats)
                ? space * 1.95
                : (prev.beats >= 4 ? space * 1.5 : space * 1.3));
      final pr = px + pWidth;
      if (prevRight == null || pr > prevRight) {
        prevRight = pr;
        prevNote = prev;
      }
      break;
    }

    var result = nominalX;
    if (prevRight != null) {
      final hasBarline =
          beatsPerBar != null &&
          beatsPerBar > 0 &&
          prevNote != null &&
          ((n.beat / beatsPerBar).floor() >
              (prevNote.beat / beatsPerBar).floor());
      final hasAccidental = _isSharp[n.pitch % 12];

      final double minX;
      if (hasBarline) {
        // Extra margin when crossing a barline: leaves clean space for the barline
        // plus pre-barline margin and post-barline accidental margin.
        minX = prevRight + (hasAccidental ? space * 3.0 : space * 2.0);
      } else if (hasAccidental) {
        minX = prevRight + space * 1.7;
      } else {
        minX = prevRight + space * 0.4;
      }

      if (result < minX) {
        result = minX;
      }
    }

    xCache?[index] = result;
    return result;
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
    final sys = systemLayout(
      staves,
      space,
      beatsPerBar: bpb,
      keyFifths: keyFifths,
    );

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
        // The frame's right edge is pushed past the screen so the staff reads
        // as endless to the right; only top, bottom and left edges are drawn.
        final frameRight = size.width + frame.strokeWidth * 2;

        if (_hasTreble) {
          final rect = Rect.fromLTRB(
            sys.systemX,
            trebleBottomY - space * 4,
            size.width,
            trebleBottomY,
          );
          canvas.drawRect(rect, band);
          canvas.drawRect(
            Rect.fromLTRB(sys.systemX, rect.top, frameRight, rect.bottom),
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
            Rect.fromLTRB(sys.systemX, rect.top, frameRight, rect.bottom),
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

      // Key signature
      if (keyFifths != 0) {
        final ksStartX = sys.clefX + space * 3.4;
        if (_hasTreble) {
          KeySignatureLayout.drawKeySignature(
            canvas: canvas,
            startX: ksStartX,
            fifths: keyFifths,
            onBass: false,
            space: space,
            trebleBottomY: trebleBottomY,
            bassTopY: bassTopY,
            color: staff,
            drawGlyph: (c, g, sz, off, clr) => _drawGlyph(c, g, sz, off, clr),
          );
        }
        if (_hasBass) {
          KeySignatureLayout.drawKeySignature(
            canvas: canvas,
            startX: ksStartX,
            fifths: keyFifths,
            onBass: true,
            space: space,
            trebleBottomY: trebleBottomY,
            bassTopY: bassTopY,
            color: staff,
            drawGlyph: (c, g, sz, off, clr) => _drawGlyph(c, g, sz, off, clr),
          );
        }
      }

      // Time signature: numerator on upper 2 spaces, denominator on lower 2 spaces.
      if (bpb != null && bpb > 0) {
        final numDigit = bpb.round();
        final numGlyph = Smufl.digitGlyph(numDigit);
        final denGlyph = Smufl.digitGlyph(
          4,
        ); // Default quarter note denominator
        final ksWidth = keyFifths != 0
            ? KeySignatureLayout.width(keyFifths, space)
            : 0.0;
        final tsX = sys.clefX + space * 3.8 + ksWidth;
        final tsSize = space * 3.4;
        if (numGlyph != null && denGlyph != null) {
          if (_hasTreble) {
            _drawGlyph(
              canvas,
              numGlyph,
              tsSize,
              Offset(tsX, trebleBottomY - space * 3),
              staff,
            );
            _drawGlyph(
              canvas,
              denGlyph,
              tsSize,
              Offset(tsX, trebleBottomY - space * 1),
              staff,
            );
          }
          if (_hasBass) {
            _drawGlyph(
              canvas,
              numGlyph,
              tsSize,
              Offset(tsX, bassTopY + space * 1),
              staff,
            );
            _drawGlyph(
              canvas,
              denGlyph,
              tsSize,
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

    // Visible window in beats.
    final now = scrollBeat.value;
    final firstBeat = now - anchorX / pixelsPerBeat - 4;
    final lastBeat = now + (size.width - anchorX) / pixelsPerBeat;
    final first = _lowerBound(firstBeat);

    final xCache = <int, double>{};
    for (var i = math.max(0, first - 10); i < notes.length; i++) {
      if (notes[i].beat > lastBeat + 2.0) break;
      noteX(
        index: i,
        notes: notes,
        anchorX: anchorX,
        nowBeat: now,
        pixelsPerBeat: pixelsPerBeat,
        space: space,
        xCache: xCache,
        beatsPerBar: bpb,
      );
    }

    if (bpb != null && bpb > 0) {
      final now0 = scrollBeat.value;
      final firstBar = ((now0 - anchorX / pixelsPerBeat) / bpb).floor();
      final lastBar = ((now0 + (size.width - anchorX) / pixelsPerBeat) / bpb)
          .ceil();
      for (var b = firstBar; b <= lastBar; b++) {
        if (b <= 0) continue;
        final barBeat = b * bpb.toDouble();
        // The final barline replaces the regular one at the end of the piece.
        if (endBeat != null && barBeat >= endBeat! - 1e-6) continue;
        final bx = barLineX(
          barBeat: barBeat,
          nowBeat: now0,
          anchorX: anchorX,
          pixelsPerBeat: pixelsPerBeat,
          space: space,
          notes: notes,
          xCache: xCache,
        );
        if (bx < clefRight) continue;
        canvas.drawLine(Offset(bx, staffTop), Offset(bx, staffBottom), ink);
      }
    }

    final end = endBeat;
    if (end != null && end > 0) {
      final ex = barLineX(
        barBeat: end,
        nowBeat: scrollBeat.value,
        anchorX: anchorX,
        pixelsPerBeat: pixelsPerBeat,
        space: space,
        notes: notes,
        xCache: xCache,
      );
      if (ex >= clefRight && ex <= size.width) {
        // MuseScore end barline (tdraw.cpp, BarLineType::END): thin line of
        // barWidth, then a thick line of endBarWidth centred endBarDistance
        // after the thin line's edge. Style defaults: 0.18, 0.55, 0.37 sp.
        final thinW = space * 0.18;
        final thickW = space * 0.55;
        final thin = Paint()
          ..color = staff
          ..strokeWidth = thinW;
        final thick = Paint()
          ..color = staff
          ..strokeWidth = thickW;
        canvas.drawLine(Offset(ex, staffTop), Offset(ex, staffBottom), thin);
        final tx = ex + thinW / 2 + space * 0.37 + thickW / 2;
        canvas.drawLine(Offset(tx, staffTop), Offset(tx, staffBottom), thick);
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

    final current = currentIndex?.call();
    double? lastX;
    final introT = introStartSec == null || clockSec == null
        ? null
        : clockSec!() - introStartSec!;
    final introOn = introT != null && introT < 1.0;
    // All scrolling elements go through one layer that is masked at the end.
    final fade = edgeFade(clefRight, anchorX, space);
    canvas.saveLayer(Offset.zero & size, Paint());
    var introN = 0;
    if (introOn) {
      for (var i = first; i < notes.length && notes[i].beat <= lastBeat; i++) {
        introN++;
      }
    }

    final beamGroups = BeamLayout.computeBeamGroups(
      notes: notes,
      first: first,
      lastBeat: lastBeat,
      onBass: _onBass,
      noteY: (pitch, onB) => _noteY(pitch, onB, l),
      noteXs: xCache,
      space: space,
      beatsPerBar: bpb,
    );
    final beamedIndices = <int>{};
    for (final g in beamGroups) {
      beamedIndices.addAll(g.allIndices);
    }

    for (final g in beamGroups) {
      BeamLayout.drawBeamGroup(
        canvas: canvas,
        group: g,
        notes: notes,
        noteY: (pitch, onB) => _noteY(pitch, onB, l),
        onBass: _onBass,
        space: space,
        defaultColor: inkColor,
        colorOf: colorOf,
      );
    }

    final tuplets = TupletLayout.computeTupletGroups(
      notes: notes,
      first: first,
      lastBeat: lastBeat,
      noteXs: xCache,
      noteY: (pitch, onB) => _noteY(pitch, onB, l),
      onBass: _onBass,
      beamedIndices: beamedIndices,
      space: space,
    );
    for (final tuplet in tuplets) {
      TupletLayout.drawTupletGroup(
        canvas: canvas,
        group: tuplet,
        space: space,
        color: inkColor,
        drawGlyph: (c, g, sz, off, clr) => _drawGlyph(c, g, sz, off, clr),
      );
    }

    // Pre-compute chord groups and notehead offsets to prevent second collisions
    final chordIndicesByGroup = <(double, bool), List<int>>{};
    for (var i = first; i < notes.length; i++) {
      final n = notes[i];
      if (n.beat > lastBeat) break;
      if (n.isSpacer || n.isRest) continue;
      final key = (n.beat, _onBass(n));
      chordIndicesByGroup.putIfAbsent(key, () => []).add(i);
    }

    final chordHeadOffsets = <int, double>{};
    for (final entry in chordIndicesByGroup.entries) {
      final group = entry.value;
      final onB = entry.key.$2;
      final chordPitches = group.map((idx) => notes[idx].pitch).toList();
      final isDown = StemLayout.computeStemDown(
        pitch: chordPitches.first,
        onBass: onB,
        explicitStemDown: notes[group.first].stemDown,
        chordPitches: chordPitches,
      );
      final offsets = ChordLayout.computeNoteheadOffsets(
        notes: notes,
        chordIndices: group,
        stemDown: isDown,
        space: space,
      );
      chordHeadOffsets.addAll(offsets);
    }

    final drawnUnisons = <(double, int, bool)>{};
    for (var i = first; i < notes.length; i++) {
      final n = notes[i];
      if (n.beat > lastBeat) break;
      final x =
          xCache[i] ??
          noteX(
            index: i,
            notes: notes,
            anchorX: anchorX,
            nowBeat: now,
            pixelsPerBeat: pixelsPerBeat,
            space: space,
            xCache: xCache,
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

      final headOffset = chordHeadOffsets[i] ?? 0.0;
      final noteXPos = x + headOffset;

      final chordKey = (n.beat, onBass);
      final chordGroup = chordIndicesByGroup[chordKey];
      final chordPitches = chordGroup?.map((idx) => notes[idx].pitch).toList();
      final noteStemDown = n.isStemDown(onBass, chordPitches: chordPitches);

      if (!isDuplicate) {
        _drawLedgers(
          canvas,
          noteXPos,
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
            Offset(noteXPos + space * (n.beats >= 4 ? 0.75 : 0.65), y),
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
        _drawGlyph(canvas, head, glyphSize, Offset(noteXPos, y), color);

        final acc = KeySignatureLayout.accidentalFor(
          pitch: n.pitch,
          keyFifths: keyFifths,
          explicit: switch (n.accidental) {
            'sharp' => AccidentalType.sharp,
            'flat' => AccidentalType.flat,
            'natural' => AccidentalType.natural,
            _ => null,
          },
        );
        if (acc != null) {
          final glyph = switch (acc) {
            AccidentalType.sharp => Smufl.accidentalSharp,
            AccidentalType.flat => Smufl.accidentalFlat,
            AccidentalType.natural => Smufl.accidentalNatural,
          };
          _drawGlyph(
            canvas,
            glyph,
            glyphSize,
            Offset(noteXPos - space * 1.3, y),
            color,
          );
        }
        if (_isDotted(n.beats)) {
          // Dot sits in a space: nudge up when the note is on a line.
          final dy = step.isEven ? -half : 0.0;
          canvas.drawCircle(
            Offset(noteXPos + space * 1.75, y + dy),
            space * 0.2,
            Paint()..color = color,
          );
        }

        if (n.tie) {
          for (var k = i + 1; k < notes.length; k++) {
            final nextN = notes[k];
            if (nextN.isSpacer || nextN.isRest) continue;
            if (nextN.pitch == n.pitch && nextN.leftHand == n.leftHand) {
              final nextX =
                  xCache[k] ??
                  noteX(
                    index: k,
                    notes: notes,
                    anchorX: anchorX,
                    nowBeat: now,
                    pixelsPerBeat: pixelsPerBeat,
                    space: space,
                    xCache: xCache,
                  );
              final nextY = _noteY(nextN.pitch, onBass, l);
              EngravingDecorations.drawTie(
                canvas,
                x1: noteXPos,
                y1: y,
                x2: nextX + (chordHeadOffsets[k] ?? 0.0),
                y2: nextY,
                space: space,
                color: color,
                tieAbove: noteStemDown,
              );
              break;
            }
          }
        }

        if (n.articulation != null) {
          EngravingDecorations.drawArticulation(
            canvas,
            articulation: n.articulation!,
            x: noteXPos,
            y: y,
            space: space,
            color: color,
            stemDown: noteStemDown,
          );
        }
      }

      if (!beamedIndices.contains(i) && n.beats < 4) {
        final strokePaint = Paint()
          ..color = color
          ..strokeWidth = math.max(1.2, space * 0.1);

        final hasOtherChordNote = chordGroup != null && chordGroup.length > 1;
        final stemDown = noteStemDown;
        final middleY = onBass
            ? bassTopY + space * 2
            : trebleBottomY - space * 2;

        final sxUp = StemLayout.stemX(
          noteheadX: noteXPos,
          stemDown: false,
          space: space,
        );
        final sxDown = StemLayout.stemX(
          noteheadX: noteXPos,
          stemDown: true,
          space: space,
        );
        final tipY = StemLayout.calcStemTipY(
          noteY: y,
          stemDown: stemDown,
          space: space,
          middleLineY: middleY,
        );

        var isLowestOfChord = true;
        var isHighestOfChord = true;
        double? chordLowestY;
        double? chordHighestY;
        if (chordGroup != null) {
          for (final idx in chordGroup) {
            final other = notes[idx];
            final otherY = _noteY(other.pitch, onBass, l);
            if (chordLowestY == null || otherY > chordLowestY) {
              chordLowestY = otherY;
            }
            if (chordHighestY == null || otherY < chordHighestY) {
              chordHighestY = otherY;
            }
            if (idx == i) continue;
            if (other.pitch < n.pitch) isLowestOfChord = false;
            if (other.pitch > n.pitch) isHighestOfChord = false;
          }
        }

        if (hasOtherChordNote) {
          // In a chord: draw a single continuous stem between all notes extending to tip
          if (stemDown) {
            if (isLowestOfChord) {
              final startY = chordHighestY ?? y;
              canvas.drawLine(
                Offset(sxDown, startY),
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
            if (isHighestOfChord) {
              final startY = chordLowestY ?? y;
              canvas.drawLine(
                Offset(sxUp, startY),
                Offset(sxUp, tipY),
                strokePaint,
              );
              if (n.beats <= 0.75) {
                final flag = n.beats <= 0.375
                    ? Smufl.flag16thUp
                    : Smufl.flag8thUp;
                _drawGlyph(canvas, flag, glyphSize, Offset(sxUp, tipY), color);
              }
            }
          }
        } else if (n.twoStems || isDuplicate) {
          final tipUpY = StemLayout.calcStemTipY(
            noteY: y,
            stemDown: false,
            space: space,
            middleLineY: middleY,
          );
          final tipDownY = StemLayout.calcStemTipY(
            noteY: y,
            stemDown: true,
            space: space,
            middleLineY: middleY,
          );
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
        } else if (stemDown) {
          canvas.drawLine(Offset(sxDown, y), Offset(sxDown, tipY), strokePaint);
          if (n.beats <= 0.75) {
            final flag = n.beats <= 0.375
                ? Smufl.flag16thDown
                : Smufl.flag8thDown;
            _drawGlyph(canvas, flag, glyphSize, Offset(sxDown, tipY), color);
          }
        } else {
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
          noteXPos,
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
    // For rapid successive sixteenth notes (beats <= 0.25), only show finger on the first note
    // of the run or on large hand shifts to avoid text collisions.
    if (n.beats <= 0.25 && prev.beats <= 0.25) {
      if ((n.pitch - prev.pitch).abs() >= 5) return true;
      if (n.beat - prev.beat >= 2.0) return true;
      return false;
    }
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
      old.endBeat != endBeat ||
      old.staves != staves ||
      old.lineRatio != lineRatio ||
      old.introStartSec != introStartSec ||
      old.pixelsPerBeat != pixelsPerBeat;
}
