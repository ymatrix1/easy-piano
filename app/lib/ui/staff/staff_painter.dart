import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'arpeggio_layout.dart';
import 'beam_layout.dart';
import 'chord_layout.dart';
import 'dynamics_layout.dart';
import 'engraving_decorations.dart';
import 'harmony_layout.dart';
import 'key_signature.dart';
import 'music_font.dart';
import 'ornament_layout.dart';
import 'ottava_layout.dart';
import 'pedal_layout.dart';
import 'repeat_layout.dart';
import 'segment_layout.dart';
import 'smufl.dart';
import 'staff_note.dart';
import 'stem_layout.dart';
import 'tuplet_layout.dart';

export 'arpeggio_layout.dart';
export 'beam_layout.dart';
export 'chord_layout.dart';
export 'dynamics_layout.dart';
export 'engraving_decorations.dart';
export 'harmony_layout.dart';
export 'key_signature.dart';
export 'ornament_layout.dart';
export 'ottava_layout.dart';
export 'segment_layout.dart';
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
/// A dynamic or hairpin being placed by [StaffPainter] (see its dynamics block).
class _Placement {
  _Placement({
    required this.x0,
    required this.x1,
    required this.height,
    required this.minDist,
    required this.between,
    required this.hairpin,
    required this.index,
  });

  final double x0;
  final double x1;
  final double height;
  final double minDist;

  /// Centred between two staves (treble dynamics on a grand staff).
  final bool between;
  final bool hairpin;

  /// Index into `dynamics` or `hairpins`.
  final int index;

  /// Top of the box, set by the layout steps.
  double top = 0;
}

class StaffPainter extends CustomPainter {
  StaffPainter({
    required List<StaffNote> notes,
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
    this.dynamics = const [],
    this.hairpins = const [],
    this.ottavas = const [],
    this.repeatBarlines = const [],
    this.voltas = const [],
    this.navigation = const [],
    this.ornaments = const [],
    this.acciaccaturas = const [],
    this.pedals = const [],
    this.arpeggios = const [],
    this.glissandi = const [],
    this.chords = const [],
    this.lyrics = const [],
    Listenable? repaintAlso,
  }) : notes = OttavaLayout.displayNotes(notes, ottavas),
       scrollBeat = playheadBeat,
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

  /// Dynamic marks (`p`..`ff`), drawn below the bottom staff at their note.
  final List<StaffDynamic> dynamics;

  /// Hairpins (crescendo / diminuendo), drawn below the bottom staff.
  final List<StaffHairpin> hairpins;

  /// Ottava spanners (`8va` / `8vb`). [notes] are stored at their displayed
  /// pitch under them (see [OttavaLayout.displayNotes]), so note indices and
  /// the audio pitches the caller holds are unchanged.
  final List<StaffOttava> ottavas;

  /// Repeat signs on bar lines (`|:`, `:|`). Each replaces the plain bar line
  /// at its beat. See [RepeatLayout].
  final List<StaffRepeatBarline> repeatBarlines;

  /// First and second endings, drawn above the top staff.
  final List<StaffVolta> voltas;

  /// Segno, coda and jump marks, drawn above the top staff at their beat.
  final List<StaffNavigation> navigation;

  /// Trills, mordents and turns above the chord (`{trill}`, `{mordent}`,
  /// `{turn}`). A trill has a wavy line to the next onset of its hand.
  final List<StaffOrnament> ornaments;

  /// Acciaccaturas (grace notes with a slash) before a chord (`{acc:"..."}`).
  final List<StaffAcciaccatura> acciaccaturas;

  /// Damper pedal spans, drawn below the bottom staff (`Ped.`, `*`, line).
  final List<StaffPedal> pedals;

  /// Arpeggio wiggles on chords, drawn left of the chord (`{arp}`).
  final List<StaffArpeggio> arpeggios;

  /// Glissando lines between two notes of one hand (`{gliss}`).
  final List<StaffGlissando> glissandi;

  /// Chord symbols, drawn above the top staff (see [HarmonyLayout]).
  final List<StaffChord> chords;

  /// Lyric syllables and extensions, drawn below the staff of their hand.
  final List<StaffLyric> lyrics;

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

  final _textCache = <String, TextPainter>{};

  /// Plain sans text for chord symbols and lyrics (not SMuFL; see
  /// [HarmonyLayout]). The default font of the app theme is used.
  TextPainter _plainText(String text, double size, Color color) {
    return _textCache.putIfAbsent('$text@$size@${color.toARGB32()}', () {
      return TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: size, color: color, height: 1),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

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
    Map<int, AccidentalType>? noteAccidentals,
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
      final hasAcc = noteAccidentals != null
          ? noteAccidentals.containsKey(i)
          : _isSharp[n.pitch % 12];
      final left = hasAcc ? nx - space * 1.3 : nx;
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
      var hasAccidental = _isSharp[n.pitch % 12];
      if (!hasAccidental) {
        for (var i = index + 1; i < notes.length; i++) {
          final other = notes[i];
          if ((other.beat - n.beat).abs() > 1e-6) break;
          if (other.leftHand == onBass && _isSharp[other.pitch % 12]) {
            hasAccidental = true;
            break;
          }
        }
      }
      if (!hasAccidental) {
        for (var i = index - 1; i >= 0; i--) {
          final other = notes[i];
          if ((other.beat - n.beat).abs() > 1e-6) break;
          if (other.leftHand == onBass && _isSharp[other.pitch % 12]) {
            hasAccidental = true;
            break;
          }
        }
      }

      final double minX;
      if (hasBarline) {
        // Extra margin when crossing a barline: leaves clean space for the barline
        // plus pre-barline margin and post-barline accidental margin.
        minX = prevRight + (hasAccidental ? space * 3.2 : space * 2.0);
      } else if (hasAccidental) {
        minX = prevRight + space * 1.8;
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

  /// Pre-computes accidental glyphs for all notes honoring MuseScore measure-level
  /// accidental memory and barline resets (`key.cpp` / `measure.cpp`).
  static Map<int, AccidentalType> computeAccidentals({
    required List<StaffNote> notes,
    required int keyFifths,
    required double? beatsPerBar,
    required bool Function(StaffNote) onBass,
  }) {
    final noteAccidentals = <int, AccidentalType>{};
    if (notes.isEmpty) return noteAccidentals;

    // Detect tied continuation notes (tied from an earlier note with same pitch & hand)
    final tiedContinuations = <int>{};
    for (var i = 0; i < notes.length; i++) {
      if (notes[i].tie) {
        for (var k = i + 1; k < notes.length; k++) {
          final nextN = notes[k];
          if (nextN.isSpacer || nextN.isRest) continue;
          if (nextN.pitch == notes[i].pitch &&
              nextN.leftHand == notes[i].leftHand) {
            tiedContinuations.add(k);
            break;
          }
        }
      }
    }

    // Sort indices chronologically by beat
    final sortedIndices = List<int>.generate(notes.length, (i) => i);
    sortedIndices.sort((a, b) => notes[a].beat.compareTo(notes[b].beat));

    final trebleState = AccidentalState(keyFifths: keyFifths);
    final bassState = AccidentalState(keyFifths: keyFifths);
    int? currentMeasure;

    for (final idx in sortedIndices) {
      final n = notes[idx];
      if (n.isSpacer || n.isRest) continue;

      if (beatsPerBar != null && beatsPerBar > 0) {
        final measure = (n.beat / beatsPerBar).floor();
        if (currentMeasure == null || measure != currentMeasure) {
          trebleState.reset();
          bassState.reset();
          currentMeasure = measure;
        }
      }

      final isBass = onBass(n);
      final state = isBass ? bassState : trebleState;
      final step = diatonicStep(n.pitch);
      final explicit = switch (n.accidental) {
        'sharp' => AccidentalType.sharp,
        'flat' => AccidentalType.flat,
        'natural' => AccidentalType.natural,
        _ => null,
      };

      final acc = state.processNote(
        step: step,
        pitch: n.pitch,
        explicit: explicit,
        isTiedContinuation: tiedContinuations.contains(idx),
      );
      if (acc != null) {
        noteAccidentals[idx] = acc;
      }
    }

    return noteAccidentals;
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

        // Classical grand staff curly brace ({) matching MuseScore Leland engraving
        EngravingDecorations.drawGrandStaffBrace(
          canvas,
          systemX: sys.systemX,
          staffTop: staffTop,
          staffBottom: staffBottom,
          space: space,
          color: inkColor,
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

    final noteAccidentals = computeAccidentals(
      notes: notes,
      keyFifths: keyFifths,
      beatsPerBar: bpb,
      onBass: _onBass,
    );

    final segments = SegmentLayout.buildSegments(
      notes: notes,
      anchorX: anchorX,
      nowBeat: now,
      pixelsPerBeat: pixelsPerBeat,
      space: space,
      beatsPerBar: bpb?.toDouble(),
      noteAccidentals: noteAccidentals,
    );
    final xCache = SegmentLayout.computeNoteXs(segments);

    // Repeat signs: their geometry is computed once here. A repeat sign
    // replaces the plain bar line at its beat (MuseScore: the BarLine item of
    // that measure boundary is START_REPEAT / END_REPEAT, not NORMAL).
    final repeatGeom = <int, RepeatBarlineGeometry>{};
    for (final r in repeatBarlines) {
      final x = SegmentLayout.barLineX(
        barBeat: r.beat,
        nowBeat: now,
        anchorX: anchorX,
        pixelsPerBeat: pixelsPerBeat,
        space: space,
        segments: segments,
      );
      repeatGeom[_beatKey(r.beat)] = RepeatLayout.barlineGeometry(
        start: r.start,
        end: r.end,
        x: x,
        space: space,
      );
    }
    bool hasRepeatAt(double beat) => repeatGeom.containsKey(_beatKey(beat));

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
        if (hasRepeatAt(barBeat)) continue;
        final bx = SegmentLayout.barLineX(
          barBeat: barBeat,
          nowBeat: now0,
          anchorX: anchorX,
          pixelsPerBeat: pixelsPerBeat,
          space: space,
          segments: segments,
        );
        if (bx < clefRight) continue;
        canvas.drawLine(Offset(bx, staffTop), Offset(bx, staffBottom), ink);
      }
    }

    final end = endBeat;
    // A repeat sign at the end of the piece draws its own closing lines.
    if (end != null && end > 0 && !hasRepeatAt(end)) {
      final ex = SegmentLayout.barLineX(
        barBeat: end,
        nowBeat: scrollBeat.value,
        anchorX: anchorX,
        pixelsPerBeat: pixelsPerBeat,
        space: space,
        segments: segments,
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

    // Repeat signs: thick and thin lines over the system, two dots in spaces
    // 2 and 3 of each staff (MuseScore TDraw::draw(BarLine), drawDots).
    final staffBottoms = [
      if (_hasTreble) trebleBottomY,
      if (_hasBass) bassTopY + space * 4,
    ];
    for (final r in repeatBarlines) {
      final g = repeatGeom[_beatKey(r.beat)]!;
      if (g.left < clefRight || g.left > size.width) continue;
      final lines = Paint()..color = staff;
      for (final x in g.thinX) {
        lines.strokeWidth = g.thinWidth;
        canvas.drawLine(Offset(x, staffTop), Offset(x, staffBottom), lines);
      }
      for (final x in g.thickX) {
        lines.strokeWidth = g.thickWidth;
        canvas.drawLine(Offset(x, staffTop), Offset(x, staffBottom), lines);
      }
      for (final bottom in staffBottoms) {
        final dotYs = RepeatLayout.dotCentresY(
          bottomLineY: bottom,
          space: space,
        );
        for (final x in g.dotsX) {
          for (final y in dotYs) {
            _drawGlyph(
              canvas,
              RepeatLayout.repeatDotGlyph,
              glyphSize,
              Offset(x, y),
              staff,
            );
          }
        }
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
      final noteXPos =
          xCache[cur0] ??
          (anchorX + (notes[cur0].beat - scrollBeat.value) * pixelsPerBeat);
      final bx = noteXPos + space * (notes[cur0].beats >= 4 ? 0.75 : 0.65);
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
      isGrandStaff: staves == Staves.grand,
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
      isGrandStaff: staves == Staves.grand,
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

    double roundBeat(double b) => (b * 10000).round() / 10000;

    // Pre-compute chord groups and notehead offsets to prevent second collisions
    final chordIndicesByGroup = <(double, bool), List<int>>{};
    for (var i = first; i < notes.length; i++) {
      final n = notes[i];
      if (n.beat > lastBeat) break;
      if (n.isSpacer || n.isRest) continue;
      final key = (roundBeat(n.beat), _onBass(n));
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

    // MuseScore parity: accidental staggering and dot conflict resolution for chords
    final chordAccidentalOffsets = <int, double>{};
    final chordDotOffsets = <int, (double, double)>{};
    for (final entry in chordIndicesByGroup.entries) {
      final group = entry.value;
      final onB = entry.key.$2;

      final accOffsets = ChordLayout.computeAccidentalOffsets(
        notes: notes,
        chordIndices: group,
        noteAccidentals: noteAccidentals,
        noteY: (pitch, onBass) => _noteY(pitch, onBass, l),
        onBass: onB,
        space: space,
      );
      chordAccidentalOffsets.addAll(accOffsets);

      final dotOffsets = ChordLayout.computeDotOffsets(
        notes: notes,
        chordIndices: group,
        chordHeadOffsets: chordHeadOffsets,
        space: space,
      );
      chordDotOffsets.addAll(dotOffsets);
    }

    final drawnUnisons = <(double, int, bool)>{};
    final drawnLedgerLines = <(double, bool, int)>{};
    // Boxes of noteheads and stems, for dynamics and hairpins to clear.
    final noteObstacles = <Rect>[];
    final drawnChordStems = <(double, bool)>{};
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
        // Whole rest hangs down from line 4; half rest sits on line 3 (MuseScore restlayout.cpp)
        final restY =
            (onBass ? bassTopY + 2 * space : trebleBottomY - 2 * space) +
            (n.voice == 2 ? (onBass ? -2 : 2) * space : 0.0) -
            (n.beats >= 4 ? space : 0.0);
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
        if (_isDotted(n.beats)) {
          canvas.drawCircle(
            Offset(x + space * 1.5, restY + space * 0.5),
            space * 0.2,
            Paint()..color = color,
          );
        }
        if (intro != null) canvas.restore();
        continue;
      }

      final step = diatonicStep(n.pitch);
      final y = _noteY(n.pitch, onBass, l);
      final noteKey = (roundBeat(n.beat), n.pitch, onBass);
      final isDuplicate = drawnUnisons.contains(noteKey);
      drawnUnisons.add(noteKey);

      final headOffset = chordHeadOffsets[i] ?? 0.0;
      final noteXPos = x + headOffset;

      final chordKey = (roundBeat(n.beat), onBass);
      final chordGroup = chordIndicesByGroup[chordKey];
      final chordPitches = chordGroup?.map((idx) => notes[idx].pitch).toList();
      final noteStemDown = n.isStemDown(
        onBass,
        chordPitches: chordPitches,
        isGrandStaff: staves == Staves.grand,
      );

      if (!isDuplicate) {
        final headW =
            (n.beats >= 4
                ? DynamicsLayout.noteheadWholeWidthSp
                : DynamicsLayout.noteheadWidthSp) *
            space;
        noteObstacles.add(
          Rect.fromLTRB(
            noteXPos,
            y - DynamicsLayout.noteheadHeightSp * space / 2,
            noteXPos + headW,
            y + DynamicsLayout.noteheadHeightSp * space / 2,
          ),
        );
        if (n.beats < 4) {
          final stemX = StemLayout.stemX(
            noteheadX: noteXPos,
            stemDown: noteStemDown,
            space: space,
          );
          final tipY = StemLayout.calcStemTipY(
            noteY: y,
            stemDown: noteStemDown,
            space: space,
            middleLineY: onBass
                ? bassTopY + space * 2
                : trebleBottomY - space * 2,
          );
          noteObstacles.add(
            Rect.fromLTRB(
              stemX - DynamicsLayout.stemSp * space / 2,
              math.min(y, tipY),
              stemX + DynamicsLayout.stemSp * space / 2,
              math.max(y, tipY),
            ),
          );
        }
        double minHeadX = noteXPos;
        double maxHeadX = noteXPos + (n.beats >= 4 ? 1.5 : 1.3) * space;
        if (chordGroup != null) {
          for (final idx in chordGroup) {
            final hx = x + (chordHeadOffsets[idx] ?? 0.0);
            final hw = (notes[idx].beats >= 4 ? 1.5 : 1.3) * space;
            if (hx < minHeadX) minHeadX = hx;
            if (hx + hw > maxHeadX) maxHeadX = hx + hw;
          }
        }
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
          minX: minHeadX,
          maxX: maxHeadX,
          drawnLedgers: drawnLedgerLines,
          beat: n.beat,
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

        final acc = noteAccidentals[i];
        if (acc != null) {
          final glyph = switch (acc) {
            AccidentalType.sharp => Smufl.accidentalSharp,
            AccidentalType.flat => Smufl.accidentalFlat,
            AccidentalType.natural => Smufl.accidentalNatural,
          };
          // In a chord, if any note is displaced left (e.g. interval of a second),
          // the accidental must sit to the left of the leftmost notehead.
          final lmOffset = chordGroup != null
              ? ChordLayout.leftmostNoteheadOffset(
                  chordIndices: chordGroup,
                  chordHeadOffsets: chordHeadOffsets,
                )
              : math.min(0.0, chordHeadOffsets[i] ?? 0.0);
          final leftmostHeadX = x + lmOffset;
          final extraShift = chordAccidentalOffsets[i] ?? 0.0;
          _drawGlyph(
            canvas,
            glyph,
            glyphSize,
            Offset(leftmostHeadX - space * 1.3 + extraShift, y),
            color,
          );
        }
        if (_isDotted(n.beats)) {
          // Dot aligns to chord and resolves vertical space conflicts (MuseScore getNoteListForDots)
          final (dotDx, dy) =
              chordDotOffsets[i] ?? (space * 1.75, step.isEven ? -half : 0.0);
          canvas.drawCircle(
            Offset(noteXPos + dotDx, y + dy),
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
              // MuseScore slurtielayout.cpp: in chords, ties bow outwards away from chord center
              final bool tieAbove;
              if (chordGroup != null && chordGroup.length > 1) {
                final minPitch = chordPitches!.reduce(math.min);
                final maxPitch = chordPitches.reduce(math.max);
                if (n.pitch == maxPitch) {
                  tieAbove = true;
                } else if (n.pitch == minPitch) {
                  tieAbove = false;
                } else {
                  tieAbove = (n.pitch - minPitch) >= (maxPitch - n.pitch);
                }
              } else {
                tieAbove = noteStemDown;
              }
              EngravingDecorations.drawTie(
                canvas,
                x1: noteXPos,
                y1: y,
                x2: nextX + (chordHeadOffsets[k] ?? 0.0),
                y2: nextY,
                space: space,
                color: color,
                tieAbove: tieAbove,
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

        if (hasOtherChordNote) {
          if (!drawnChordStems.contains(chordKey)) {
            drawnChordStems.add(chordKey);
            // In a chord: draw a single continuous stem between all notes extending to tip.
            // The stem attaches to the normal (undisplaced) side of the chord noteheads at `x`.
            final chordStemXDown = StemLayout.stemX(
              noteheadX: x,
              stemDown: true,
              space: space,
            );
            final chordStemXUp = StemLayout.stemX(
              noteheadX: x,
              stemDown: false,
              space: space,
            );

            // Compute vertical extremes of the chord
            double minY = y; // highest pitch (lowest screen Y)
            double maxY = y; // lowest pitch (highest screen Y)
            for (final idx in chordGroup) {
              final ny = _noteY(notes[idx].pitch, onBass, l);
              if (ny < minY) minY = ny;
              if (ny > maxY) maxY = ny;
            }

            if (stemDown) {
              final chordTipY = StemLayout.calcStemTipY(
                noteY: maxY,
                stemDown: true,
                space: space,
                middleLineY: middleY,
              );
              canvas.drawLine(
                Offset(chordStemXDown, minY),
                Offset(chordStemXDown, chordTipY),
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
                  Offset(chordStemXDown, chordTipY),
                  color,
                );
              }
            } else {
              final chordTipY = StemLayout.calcStemTipY(
                noteY: minY,
                stemDown: false,
                space: space,
                middleLineY: middleY,
              );
              canvas.drawLine(
                Offset(chordStemXUp, maxY),
                Offset(chordStemXUp, chordTipY),
                strokePaint,
              );
              if (n.beats <= 0.75) {
                final flag = n.beats <= 0.375
                    ? Smufl.flag16thUp
                    : Smufl.flag8thUp;
                _drawGlyph(
                  canvas,
                  flag,
                  glyphSize,
                  Offset(chordStemXUp, chordTipY),
                  color,
                );
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

    // Ornaments and acciaccaturas (MuseScore tlayout.cpp, chordlayout.cpp).
    if (ornaments.isNotEmpty || acciaccaturas.isNotEmpty) {
      _drawOrnamentsAndAcciaccaturas(
        canvas,
        l: l,
        glyphSize: glyphSize,
        color: staff,
        headX: (i) =>
            (xCache[i] ??
                noteX(
                  index: i,
                  notes: notes,
                  anchorX: anchorX,
                  nowBeat: now,
                  pixelsPerBeat: pixelsPerBeat,
                  space: l.space,
                  xCache: xCache,
                )) +
            (chordHeadOffsets[i] ?? 0.0),
      );
    }

    // Arpeggios and glissandi (MuseScore arpeggiolayout.cpp, tlayout.cpp).
    if (arpeggios.isNotEmpty || glissandi.isNotEmpty) {
      _drawArpeggiosAndGlissandi(
        canvas,
        l: l,
        glyphSize: glyphSize,
        color: staff,
        xOf: (i) =>
            xCache[i] ??
            noteX(
              index: i,
              notes: notes,
              anchorX: anchorX,
              nowBeat: now,
              pixelsPerBeat: pixelsPerBeat,
              space: l.space,
              xCache: xCache,
            ),
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
          _noteY(
            OttavaLayout.displayPitch(
              b.pitch,
              ottavas: ottavas,
              beat: b.beat,
              leftHand: b.leftHand,
            ),
            onBass,
            l,
          ),
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

    if (chords.isNotEmpty || lyrics.isNotEmpty) {
      _drawChordsAndLyrics(
        canvas,
        size: size,
        l: l,
        anchorX: anchorX,
        now: now,
        xCache: xCache,
        headOffsets: chordHeadOffsets,
        color: staff,
      );
    }

    // Voltas: horizontal line above the top staff, hook at the left end and
    // at the right end when the ending closes with a repeat (volta.cpp).
    for (final v in voltas) {
      final startX = RepeatLayout.voltaStartX(
        barX: SegmentLayout.barLineX(
          barBeat: v.startBeat,
          nowBeat: now,
          anchorX: anchorX,
          pixelsPerBeat: pixelsPerBeat,
          space: space,
          segments: segments,
        ),
        group: repeatGeom[_beatKey(v.startBeat)],
        space: space,
      );
      final endX = RepeatLayout.voltaEndX(
        barX: SegmentLayout.barLineX(
          barBeat: v.endBeat,
          nowBeat: now,
          anchorX: anchorX,
          pixelsPerBeat: pixelsPerBeat,
          space: space,
          segments: segments,
        ),
        group: repeatGeom[_beatKey(v.endBeat)],
        space: space,
      );
      if (endX <= startX || endX < clefRight || startX > size.width) continue;
      final vg = RepeatLayout.voltaGeometry(
        startX: startX,
        endX: endX,
        staffTopY: staffTop,
        space: space,
        closedEnd: v.closedEnd,
      );
      final vp = Paint()
        ..color = staff
        ..strokeWidth = RepeatLayout.voltaLineWidthSp * space;
      canvas.drawLine(
        Offset(vg.startX, vg.lineY),
        Offset(vg.endX, vg.lineY),
        vp,
      );
      canvas.drawLine(
        Offset(vg.startX, vg.lineY),
        Offset(vg.startX, vg.hookBottomY),
        vp,
      );
      if (vg.closedEnd) {
        canvas.drawLine(
          Offset(vg.endX, vg.lineY),
          Offset(vg.endX, vg.hookBottomY),
          vp,
        );
      }
      // Label below the line, bold, 11 pt spatium-dependent (volta.cpp:109,
      // v450:497-500). Font face is local, see RepeatLayout.
      _drawText(
        canvas,
        '${v.number}.',
        origin: vg.labelOrigin,
        fontSize: RepeatLayout.voltaFontSize(space),
        color: staff,
        fontWeight: FontWeight.bold,
      );
    }

    // Navigation marks above the top staff, at the note's x when a note sits
    // on the beat, else at the beat's nominal x. Under a volta they sit higher.
    for (final nav in navigation) {
      final i = _lowerBound(nav.beat - 1e-6);
      final onNote =
          i < notes.length && (notes[i].beat - nav.beat).abs() < 1e-6;
      final x = onNote && xCache.containsKey(i)
          ? xCache[i]!
          : anchorX + (nav.beat - now) * pixelsPerBeat;
      if (x < clefRight || x > size.width) continue;
      final baseY = RepeatLayout.navigationBaselineY(
        staffTopY: staffTop,
        space: space,
        overVolta: RepeatLayout.withinVolta(nav.beat, voltas),
      );
      final glyph = RepeatLayout.navigationGlyph(nav.kind);
      if (glyph != null) {
        // Segno and coda: 18 pt symbol, centred on x (marker.cpp:180-183).
        _drawGlyph(
          canvas,
          glyph,
          RepeatLayout.navigationGlyphEm(space),
          Offset(
            RepeatLayout.navigationGlyphOriginX(
              kind: nav.kind,
              x: x,
              space: space,
            ),
            baseY,
          ),
          staff,
        );
      } else {
        // Jump text: 11 pt, normal style (v450:1094-1097).
        _drawText(
          canvas,
          RepeatLayout.navigationLabel(nav.kind)!,
          origin: Offset(x, baseY),
          fontSize: RepeatLayout.jumpFontSize(space),
          color: staff,
        );
      }
    }

    // Dynamics and hairpins (MuseScore dynamicslayout.cpp, tlayout.cpp
    // layoutHairpinSegment, systemlayout.cpp centerItemGroup, autoplace).
    if (hairpins.isNotEmpty ||
        dynamics.isNotEmpty ||
        ottavas.isNotEmpty ||
        pedals.isNotEmpty) {
      final grand = staves == Staves.grand;
      final gapMidY = (trebleBottomY + bassTopY) / 2;

      // Index of the note at [beat], or -1 when none sits there.
      int noteIndexAt(double beat) {
        final i = _lowerBound(beat - 1e-6);
        if (i < notes.length && (notes[i].beat - beat).abs() < 1e-6) {
          return i;
        }
        return -1;
      }

      // Note x (left edge of the notehead) at [beat], or the nominal x.
      double xAt(double beat) {
        final i = noteIndexAt(beat);
        if (i >= 0) {
          final cx = xCache[i];
          if (cx != null) return cx;
        }
        return anchorX + (beat - now) * pixelsPerBeat;
      }

      // Barline x positions in view, for horizontal clearance.
      final barXs = <double>[
        if (bpb != null && bpb > 0)
          for (
            var b = ((now - anchorX / pixelsPerBeat) / bpb).floor();
            b <= ((now + (size.width - anchorX) / pixelsPerBeat) / bpb).ceil();
            b++
          )
            if (b > 0)
              SegmentLayout.barLineX(
                barBeat: b * bpb,
                nowBeat: now,
                anchorX: anchorX,
                pixelsPerBeat: pixelsPerBeat,
                space: space,
                segments: segments,
              ),
      ];

      // Staff lines as zero-height obstacles; the gap between two staves is
      // bounded by them.
      final staffLineBoxes = <Rect>[
        if (_hasTreble)
          Rect.fromLTRB(sys.systemX, trebleBottomY, size.width, trebleBottomY),
        if (_hasBass)
          Rect.fromLTRB(sys.systemX, bassTopY, size.width, bassTopY),
      ];
      final noteBoxes = [...staffLineBoxes, ...noteObstacles];
      final dynMin = DynamicsLayout.dynamicsMinDistanceSp * space;
      final hpMin = DynamicsLayout.hairpinMinDistanceSp * space;
      final hpDynDist = DynamicsLayout.hairpinDynamicsDistanceSp * space;

      // Every item with its horizontal extent, in left-to-right order.
      final items = <_Placement>[];
      for (var k = 0; k < hairpins.length; k++) {
        final h = hairpins[k];
        final x1 = xAt(h.startBeat);
        final x2 = math.max(xAt(h.endBeat), x1 + space);
        if (x2 < 0 || x1 > size.width) continue;
        items.add(
          _Placement(
            x0: x1,
            x1: x2,
            height: DynamicsLayout.hairpinBoxSp * space,
            minDist: hpMin,
            between: grand && !h.leftHand,
            hairpin: true,
            index: k,
          ),
        );
      }
      for (var k = 0; k < dynamics.length; k++) {
        final d = dynamics[k];
        final glyphs = DynamicsLayout.glyphsFor(d.mark);
        if (glyphs == null) continue;
        final width = _glyph(glyphs, glyphSize, staff).width;
        // centerOnNotehead: the text is centred on the notehead's middle.
        final i = noteIndexAt(d.beat);
        final centre = i >= 0
            ? (xCache[i] ?? anchorX) +
                  (chordHeadOffsets[i] ?? 0.0) +
                  DynamicsLayout.noteheadCentreSp(whole: notes[i].beats >= 4) *
                      space
            : anchorX +
                  (d.beat - now) * pixelsPerBeat +
                  DynamicsLayout.noteheadCentreSp(whole: false) * space;
        var left = DynamicsLayout.dynamicLeft(centreX: centre, width: width);
        if (left > size.width || left + width < 0) continue;
        left += DynamicsLayout.barlineShift(
          left: left,
          right: left + width,
          barlineXs: barXs,
          space: space,
        );
        items.add(
          _Placement(
            x0: left,
            x1: left + width,
            height: DynamicsLayout.boxHeightSp(d.mark) * space,
            minDist: dynMin,
            between: grand && !d.leftHand,
            hairpin: false,
            index: k,
          ),
        );
      }
      items.sort((a, b) => a.x0.compareTo(b.x0));

      // 1. Preferred tops. Items between two staves are centred in the gap
      //    against the staff lines and noteheads; the others go below their
      //    staff and are pushed past what is in the way.
      final belowPlaced = <Rect>[];
      for (final it in items) {
        if (it.between) {
          final (upper, lower) = DynamicsLayout.gapEdges(
            x0: it.x0,
            x1: it.x1,
            gapMidY: gapMidY,
            obstacles: noteBoxes,
            upperDefault: trebleBottomY,
            lowerDefault: bassTopY,
          );
          it.top = DynamicsLayout.centredTop(
            upperBottom: upper,
            lowerTop: lower,
            height: it.height,
            minDist: it.minDist,
          );
        } else {
          final nominal = it.hairpin
              ? DynamicsLayout.hairpinNominalTop(
                  bottomStaffY: staffBottom,
                  space: space,
                )
              : DynamicsLayout.dynamicNominalTop(
                  bottomStaffY: staffBottom,
                  space: space,
                );
          var top = DynamicsLayout.clearBelow(
            top: nominal,
            height: it.height,
            x0: it.x0,
            x1: it.x1,
            minDist: it.minDist,
            obstacles: noteBoxes,
          );
          top = DynamicsLayout.clearBelow(
            top: top,
            height: it.height,
            x0: it.x0,
            x1: it.x1,
            minDist: hpDynDist,
            obstacles: belowPlaced,
          );
          it.top = top;
          belowPlaced.add(Rect.fromLTWH(it.x0, top, it.x1 - it.x0, it.height));
        }
      }

      // 2. Between-staves items that overlap horizontally form one group. The
      //    group is stacked and centred as one unit (centerItemGroup).
      final groups = <List<_Placement>>[];
      for (final it in items.where((i) => i.between)) {
        final hit = [
          for (final g in groups)
            if (g.any((m) => m.x0 < it.x1 && it.x0 < m.x1)) g,
        ];
        final merged = [it];
        for (final g in hit) {
          groups.remove(g);
          merged.addAll(g);
        }
        groups.add(merged);
      }
      for (final g in groups) {
        final (rel, height) = DynamicsLayout.stackGroup(
          natural: [for (final m in g) m.top],
          heights: [for (final m in g) m.height],
          gaps: [for (final m in g) m.minDist],
        );
        final (upper, lower) = DynamicsLayout.gapEdges(
          x0: g.map((m) => m.x0).reduce(math.min),
          x1: g.map((m) => m.x1).reduce(math.max),
          gapMidY: gapMidY,
          obstacles: noteBoxes,
          upperDefault: trebleBottomY,
          lowerDefault: bassTopY,
        );
        final groupTop = DynamicsLayout.centredTop(
          upperBottom: upper,
          lowerTop: lower,
          height: height,
          minDist: g.map((m) => m.minDist).reduce(math.max),
        );
        for (var k = 0; k < g.length; k++) {
          g[k].top = groupTop + rel[k];
        }
      }

      // 3. Draw.
      for (final it in items) {
        if (it.hairpin) {
          DynamicsLayout.drawHairpin(
            canvas,
            x1: it.x0,
            x2: it.x1,
            centreY: it.top + it.height / 2,
            space: space,
            kind: hairpins[it.index].kind,
            color: staff,
          );
        } else {
          final mark = dynamics[it.index].mark;
          _drawGlyph(
            canvas,
            DynamicsLayout.glyphsFor(mark)!,
            glyphSize,
            Offset(it.x0, it.top + DynamicsLayout.ascentSp(mark) * space),
            staff,
          );
        }
      }

      // Ottava lines, same x mapping as the hairpins above.
      _drawOttavas(canvas, l, xAt, staff);

      // Damper pedal (MuseScore dom/pedal.cpp linePos, tlayout.cpp
      // layoutPedalSegment). Below the bottom staff, clear of noteheads.
      for (final p in pedals) {
        final downX = xAt(p.startBeat);
        final endPointX =
            xAt(p.endBeat) -
            (p.released ? PedalLayout.releaseOffsetSp * space : 0.0);
        final pedWidth = _glyph(PedalLayout.pedGlyph, glyphSize, staff).width;
        final starWidth = _glyph(PedalLayout.starGlyph, glyphSize, staff).width;
        final x0 = downX - PedalLayout.startOffsetSp * space;
        final x1 =
            endPointX +
            (p.released ? PedalLayout.starGapSp * space + starWidth : 0.0);
        if (x1 < 0 || x0 > size.width) continue;
        final lineY = PedalLayout.lineY(
          bottomStaffY: staffBottom,
          space: space,
          x0: x0,
          x1: x1,
          obstacles: noteBoxes,
        );
        final g = PedalLayout.geometry(
          space: space,
          lineY: lineY,
          downX: downX,
          endPointX: endPointX,
          released: p.released,
          changeX: [
            for (final c in p.changeBeats)
              xAt(c) - PedalLayout.changeOffsetSp * space,
          ],
          pedWidth: pedWidth,
        );
        _drawGlyph(
          canvas,
          PedalLayout.pedGlyph,
          glyphSize,
          Offset(g.pedX, g.lineY),
          staff,
        );
        if (g.released) {
          _drawGlyph(
            canvas,
            PedalLayout.starGlyph,
            glyphSize,
            Offset(g.starX, g.lineY),
            staff,
          );
        }
        PedalLayout.draw(canvas, g, space: space, color: staff);
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

  /// Chord symbols above the top staff, and lyrics below the staff of their
  /// hand (MuseScore harmonylayout.cpp, lyricslayout.cpp). Geometry is in
  /// [HarmonyLayout]; this method only measures text and paints it.
  void _drawChordsAndLyrics(
    Canvas canvas, {
    required Size size,
    required ({double space, double trebleBottomY, double bassTopY}) l,
    required double anchorX,
    required double now,
    required Map<int, double> xCache,
    required Map<int, double> headOffsets,
    required Color color,
  }) {
    final space = l.space;
    final ppb = pixelsPerBeat;
    final width = size.width;

    // Indices of the notes that start at [beat].
    Iterable<int> indicesAt(double beat) sync* {
      for (
        var i = lowerBound(notes, beat - 1e-6);
        i < notes.length && (notes[i].beat - beat).abs() < 1e-6;
        i++
      ) {
        yield i;
      }
    }

    // Left edge of the notehead of note [i], including chord displacement.
    double headLeft(int i) =>
        (xCache[i] ??
            noteX(
              index: i,
              notes: notes,
              anchorX: anchorX,
              nowBeat: now,
              pixelsPerBeat: ppb,
              space: space,
              xCache: xCache,
              beatsPerBar: beatsPerBar,
            )) +
        (headOffsets[i] ?? 0.0);

    // The note of hand [leftHand] at [beat]; another hand's note when that
    // hand has none there.
    int? noteAt(double beat, bool leftHand) {
      int? any;
      for (final i in indicesAt(beat)) {
        final n = notes[i];
        if (n.isSpacer) continue;
        if (n.leftHand == leftHand) return i;
        any ??= i;
      }
      return any;
    }

    // Chords: left aligned on the note (chordSymbolAAlign left, v450 mss:296),
    // 2.5 sp above the top staff line or lifted above the highest notehead at
    // their onset.
    final chordTop = _hasTreble ? l.trebleBottomY - space * 4 : l.bassTopY;
    final rootPx = space * HarmonyLayout.chordSizeSp;
    for (final c in chords) {
      final i = noteAt(c.beat, c.leftHand);
      final x = i == null ? anchorX + (c.beat - now) * ppb : headLeft(i);
      double? noteTop;
      for (final j in indicesAt(c.beat)) {
        final n = notes[j];
        if (n.isSpacer || n.isRest) continue;
        final top =
            _noteY(n.pitch, _onBass(n), l) -
            DynamicsLayout.noteheadHeightSp * space / 2;
        noteTop = noteTop == null ? top : math.min(noteTop, top);
      }
      final baseline = HarmonyLayout.chordBaselineY(
        staffTopY: chordTop,
        noteTopY: noteTop,
        space: space,
      );
      final runs = [
        for (final r in HarmonyLayout.chordRuns(c.symbol))
          (
            tp: _plainText(r.text, rootPx * r.scale, color),
            rise: r.riseSp * space,
            dx: r.dxSp * space,
          ),
      ];
      final total = runs.fold(0.0, (w, r) => w + r.tp.width);
      if (x > width || x + total < 0) continue;
      var cx = x;
      for (final r in runs) {
        final base = baseline - r.rise;
        r.tp.paint(
          canvas,
          Offset(
            cx + r.dx,
            base -
                r.tp.computeDistanceToActualBaseline(TextBaseline.alphabetic),
          ),
        );
        cx += r.tp.width;
      }
    }

    if (lyrics.isEmpty) return;
    final lyricPx = space * HarmonyLayout.lyricSizeSp;
    final ref = _plainText('Ag', lyricPx, color);
    final baseOffset = ref.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    final lineW = math.max(1.2, HarmonyLayout.lineThicknessSp * space);
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = lineW;

    for (final hand in const [false, true]) {
      // Items of this hand in beat order.
      final row = [
        for (final s in lyrics)
          if (s.leftHand == hand) s,
      ]..sort((a, b) => a.beat.compareTo(b.beat));
      if (row.isEmpty) continue;

      // Staff of this hand: the bass staff for LH on a grand staff.
      final onBassStaff = switch (staves) {
        Staves.treble => false,
        Staves.bass => true,
        Staves.grand => hand,
      };
      final staffBottomY = onBassStaff
          ? l.bassTopY + space * 4
          : l.trebleBottomY;
      final middleY = onBassStaff
          ? l.bassTopY + space * 2
          : l.trebleBottomY - space * 2;

      // Lowest ink of the notes at each lyric's onset (heads and down stems).
      double? lowestInkAt(double beat) {
        double? lowest;
        for (final j in indicesAt(beat)) {
          final m = notes[j];
          if (m.isSpacer || m.isRest || m.leftHand != hand) continue;
          final y = _noteY(m.pitch, onBassStaff, l);
          var bottom = y + DynamicsLayout.noteheadHeightSp * space / 2;
          if (m.beats < 4 &&
              m.isStemDown(onBassStaff, isGrandStaff: staves == Staves.grand)) {
            bottom = math.max(
              bottom,
              StemLayout.calcStemTipY(
                noteY: y,
                stemDown: true,
                space: space,
                middleLineY: middleY,
              ),
            );
          }
          lowest = lowest == null ? bottom : math.max(lowest, bottom);
        }
        return lowest;
      }

      final slots = <_LyricSlot>[];
      double? rowLowest;
      for (final s in row) {
        final i = noteAt(s.beat, hand);
        final whole = i != null && notes[i].beats >= 4;
        final centre = i == null
            ? anchorX +
                  (s.beat - now) * ppb +
                  DynamicsLayout.noteheadCentreSp(whole: false) * space
            : headLeft(i) +
                  DynamicsLayout.noteheadCentreSp(whole: whole) * space;
        final width = s.isExtension
            ? 0.0
            : _plainText(s.text, lyricPx, color).width;
        final slot = _LyricSlot(
          s,
          centre: centre,
          width: width,
          headRight:
              centre + HarmonyLayout.headWidthSp(whole: whole) * space / 2,
        );
        slots.add(slot);
        final low = lowestInkAt(s.beat);
        if (low != null) {
          rowLowest = rowLowest == null ? low : math.max(rowLowest, low);
        }
      }

      // One baseline for the whole row of this hand, so syllables line up
      // even where stems differ in length.
      final baseline = HarmonyLayout.lyricBaselineY(
        staffBottomY: staffBottomY,
        lowestInkY: rowLowest,
        ascent: baseOffset,
        space: space,
      );
      for (final slot in slots) {
        slot
          ..boxTop = baseline - baseOffset
          ..baseline = baseline;
      }

      for (var k = 0; k < slots.length; k++) {
        final slot = slots[k];
        final s = slot.lyric;
        if (slot.right < 0 || slot.left > width) continue;
        if (!s.isExtension) {
          _plainText(
            s.text,
            lyricPx,
            color,
          ).paint(canvas, Offset(slot.left, slot.boxTop));
        }
        final y = HarmonyLayout.dashY(baselineY: slot.baseline, space: space);
        if (s.hyphen && !s.isExtension && k + 1 < slots.length) {
          final next = slots[k + 1];
          if (!next.lyric.isExtension) {
            for (final seg in HarmonyLayout.hyphenSegments(
              prevRight: slot.right,
              nextLeft: next.left,
              space: space,
            )) {
              canvas.drawLine(Offset(seg.x0, y), Offset(seg.x1, y), linePaint);
            }
          }
        }
        if (s.isExtension &&
            (k + 1 >= slots.length || !slots[k + 1].lyric.isExtension)) {
          // A melisma ends at the last extension of its run, and starts after
          // the syllable before the run (lyricslayout.cpp:782-841).
          var j = k - 1;
          while (j >= 0 && slots[j].lyric.isExtension) {
            j--;
          }
          if (j >= 0) {
            final seg = HarmonyLayout.melismaSegment(
              textRight: slots[j].right,
              headRight: slot.headRight,
              space: space,
            );
            if (seg != null) {
              canvas.drawLine(Offset(seg.x0, y), Offset(seg.x1, y), linePaint);
            }
          }
        }
      }
    }
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
    double? minX,
    double? maxX,
    Set<(double, bool, int)>? drawnLedgers,
    double beat = 0.0,
  }) {
    // Ledger lines extend past the notehead equally on both sides.
    // In chords, spans from the leftmost to the rightmost notehead (MuseScore chordlayout.cpp).
    final left = (minX ?? x) - space * 0.45;
    final right = (maxX ?? (x + headWidth)) + space * 0.45;

    void drawLine(int s, double ly) {
      if (drawnLedgers != null && !drawnLedgers.add((beat, bass, s))) {
        return;
      }
      canvas.drawLine(Offset(left, ly), Offset(right, ly), ink);
    }

    if (!bass && step < _trebleBottomStep) {
      for (var s = _trebleBottomStep - 2; s >= step; s -= 2) {
        final ly = trebleBottomY + (_trebleBottomStep - s) * half;
        drawLine(s, ly);
      }
    }
    if (!bass && step > _trebleBottomStep + 8) {
      for (var s = _trebleBottomStep + 10; s <= step; s += 2) {
        final ly = trebleBottomY - (s - _trebleBottomStep) * half;
        drawLine(s, ly);
      }
    }
    if (bass && step > _bassTopStep) {
      for (var s = _bassTopStep + 2; s <= step; s += 2) {
        final ly = bassTopY - (s - _bassTopStep) * half;
        drawLine(s, ly);
      }
    }
    if (bass && step < _bassTopStep - 8) {
      for (var s = _bassTopStep - 10; s >= step; s -= 2) {
        final ly = bassTopY + (_bassTopStep - s) * half;
        drawLine(s, ly);
      }
    }
  }

  /// Map key for a beat, so that float noise in bar and note beats match.
  static int _beatKey(double beat) => (beat * 1000).round();

  /// Draws plain text (volta numbers, D.C. / D.S. labels) with its baseline
  /// origin at [origin]. Text uses the app's default font, not Leland.
  void _drawText(
    Canvas canvas,
    String text, {
    required Offset origin,
    required double fontSize,
    required Color color,
    FontWeight fontWeight = FontWeight.normal,
    FontStyle fontStyle = FontStyle.normal,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final baseline = tp.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    tp.paint(canvas, Offset(origin.dx, origin.dy - baseline));
    tp.dispose();
  }

  /// Ornaments above their chord and acciaccaturas before their chord.
  /// Mordents and turns are centred on the head and placed as MuseScore's
  /// `layoutArticulations` does. A trill starts at the chord origin and is
  /// drawn as glyphs (`ornamentTrill` then `wiggleTrill` fills) up to the next
  /// onset of its hand. [headX] gives the left ink edge of a note index, chord
  /// displacement included.
  void _drawOrnamentsAndAcciaccaturas(
    Canvas canvas, {
    required ({double space, double trebleBottomY, double bassTopY}) l,
    required double glyphSize,
    required Color color,
    required double Function(int index) headX,
  }) {
    final space = l.space;
    bool onBassOf(bool leftHand) =>
        staves == Staves.grand ? leftHand : staves == Staves.bass;

    // Sounding notes of one hand at one onset (a chord), by index.
    List<int> chordAt(double beat, bool leftHand) {
      final out = <int>[];
      var i = lowerBound(notes, beat - 1e-6);
      while (i < notes.length && (notes[i].beat - beat).abs() < 1e-6) {
        final n = notes[i];
        if (n.leftHand == leftHand && !n.isRest && !n.isSpacer) out.add(i);
        i++;
      }
      return out;
    }

    // Onset of the next sounding note of one hand after [beat], if any.
    double? nextOnset(double beat, bool leftHand) {
      for (var i = lowerBound(notes, beat + 1e-6); i < notes.length; i++) {
        final n = notes[i];
        if (n.leftHand == leftHand && !n.isRest && !n.isSpacer) return n.beat;
      }
      return null;
    }

    // Staff top line of the hand's staff (screen y).
    double staffTopOf(bool onBass) =>
        onBass ? l.bassTopY : l.trebleBottomY - space * 4;

    // Chord geometry for ornament placement, as MuseScore lays it out.
    // Stem direction and tip come from the chord, not from each note.
    ({
      double topY,
      double topX,
      double lowestY,
      bool stemUp,
      List<double> heads,
    })
    chordGeometry(List<int> idx, bool onBass) {
      final chordPitches = [for (final i in idx) notes[i].pitch];
      final heads = <double>[];
      var topIdx = idx.first;
      var topY = double.infinity;
      var lowestY = double.negativeInfinity;
      for (final i in idx) {
        final y = _noteY(notes[i].pitch, onBass, l);
        heads.add(y);
        if (y < topY) {
          topY = y;
          topIdx = i;
        }
        lowestY = math.max(lowestY, y);
      }
      final stemUp = !notes[topIdx].isStemDown(
        onBass,
        chordPitches: chordPitches,
        isGrandStaff: staves == Staves.grand,
      );
      return (
        topY: topY,
        topX: headX(topIdx),
        lowestY: lowestY,
        stemUp: stemUp,
        heads: heads,
      );
    }

    for (final o in ornaments) {
      final idx = chordAt(o.beat, o.leftHand);
      if (idx.isEmpty) continue;
      final onBass = onBassOf(o.leftHand);
      final middleLineY = onBass
          ? l.bassTopY + space * 2
          : l.trebleBottomY - space * 2;
      final c = chordGeometry(idx, onBass);
      // Tip of a stem-up chord: its stem starts at the lowest note. Only used
      // when the stem is up (a stem-down chord has no tip above it).
      final stemTipY = c.stemUp
          ? StemLayout.calcStemTipY(
              noteY: c.lowestY,
              stemDown: false,
              space: space,
              middleLineY: middleLineY,
            )
          : c.topY;

      if (o.kind == OrnamentKind.trill) {
        // Trill: the start glyph sits at the chord origin, the wavy line runs
        // to the next onset of its hand. Autoplace places it above the chord.
        final topInk = OrnamentLayout.topInkY(
          headYs: c.heads,
          stemTipYs: c.stemUp ? [stemTipY] : const [],
          space: space,
        );
        final baseline = OrnamentLayout.trillBaselineY(
          staffTopY: staffTopOf(onBass),
          topInkY: topInk,
          space: space,
        );
        var startX = double.infinity;
        for (final i in idx) {
          startX = math.min(startX, headX(i));
        }
        final next = nextOnset(o.beat, o.leftHand);
        var endX = startX;
        if (next != null) {
          var nextOrigin = double.infinity;
          for (final i in chordAt(next, o.leftHand)) {
            nextOrigin = math.min(nextOrigin, headX(i));
          }
          // An acciaccatura before the next onset stops the line before its
          // grace head (`dom/trill.cpp:282`-`:295`).
          for (final a in acciaccaturas) {
            if (a.leftHand != o.leftHand || (a.beat - next).abs() > 1e-6) {
              continue;
            }
            final nextIdx = chordAt(next, o.leftHand);
            final leftmost = OrnamentLayout.leftmostInk(
              notes: [
                for (final i in nextIdx)
                  (headX: headX(i), accidental: notes[i].accidental),
              ],
              space: space,
            );
            nextOrigin = math.min(
              nextOrigin,
              OrnamentLayout.graceHeadLeftX(
                leftmostInkX: leftmost,
                space: space,
              ),
            );
          }
          endX = OrnamentLayout.trillEndX(
            nextOriginX: nextOrigin,
            space: space,
          );
        }
        final sym = OrnamentLayout.trillSymbols(
          startX: startX,
          endX: endX,
          space: space,
        );
        _drawGlyph(
          canvas,
          OrnamentLayout.trill.glyph,
          glyphSize,
          Offset(sym.startX, baseline),
          color,
        );
        for (final x in sym.fillXs) {
          _drawGlyph(
            canvas,
            OrnamentLayout.wiggle.glyph,
            glyphSize,
            Offset(x, baseline),
            color,
          );
        }
        continue;
      }

      // Mordent and turn: above the chord (stem tip for stem-up chords, the
      // top notehead otherwise), or above the staff when the chord is low.
      final chordTopY = OrnamentLayout.ornamentChordTopY(
        stemUp: c.stemUp,
        stemTipY: stemTipY,
        topHeadY: c.topY,
        space: space,
      );
      final origin = OrnamentLayout.ornamentOrigin(
        kind: o.kind,
        centreX: OrnamentLayout.headCentreX(c.topX, space),
        baselineY: OrnamentLayout.ornamentBaselineY(
          staffTopY: staffTopOf(onBass),
          chordTopY: chordTopY,
          space: space,
        ),
        space: space,
      );
      _drawGlyph(
        canvas,
        OrnamentLayout.glyphFor(o.kind).glyph,
        glyphSize,
        origin,
        color,
      );
    }

    for (final a in acciaccaturas) {
      final idx = chordAt(a.beat, a.leftHand);
      if (idx.isEmpty) continue;
      final onBass = onBassOf(a.leftHand);
      final leftmost = OrnamentLayout.leftmostInk(
        notes: [
          for (final i in idx)
            (headX: headX(i), accidental: notes[i].accidental),
        ],
        space: space,
      );
      final graceLeft = OrnamentLayout.graceHeadLeftX(
        leftmostInkX: leftmost,
        space: space,
      );
      final y = _noteY(a.pitch, onBass, l);
      final graceSize = glyphSize * OrnamentLayout.graceNoteMag;

      final accGlyph = switch (a.accidental) {
        'sharp' => Smufl.accidentalSharp,
        'flat' => Smufl.accidentalFlat,
        'natural' => Smufl.accidentalNatural,
        _ => null,
      };
      if (accGlyph != null) {
        _drawGlyph(
          canvas,
          accGlyph,
          graceSize,
          Offset(
            OrnamentLayout.graceAccidentalX(
              graceLeftX: graceLeft,
              accidental: a.accidental!,
              space: space,
            ),
            y,
          ),
          color,
        );
      }

      final graceHeadWidth =
          OrnamentLayout.headWidthSp * OrnamentLayout.graceNoteMag * space;
      _drawLedgers(
        canvas,
        graceLeft,
        y,
        onBass,
        diatonicStep(a.pitch),
        space / 2,
        space,
        l.trebleBottomY,
        l.bassTopY,
        Paint()
          ..color = color
          ..strokeWidth = math.max(1.2, space * 0.09),
        headWidth: graceHeadWidth,
        minX: graceLeft,
        maxX: graceLeft + graceHeadWidth,
        beat: a.beat,
      );
      _drawGlyph(
        canvas,
        Smufl.noteheadBlack,
        graceSize,
        Offset(graceLeft, y),
        color,
      );

      final stemX = OrnamentLayout.graceStemX(
        graceLeftX: graceLeft,
        space: space,
      );
      final tipY = y - OrnamentLayout.graceStemLength(space);
      canvas.drawLine(
        Offset(stemX, y),
        Offset(stemX, tipY),
        Paint()
          ..color = color
          ..strokeWidth = OrnamentLayout.graceStemWidth(space),
      );
      // The slash is a line through the stem (MuseScore layoutStemSlash).
      final slash = OrnamentLayout.stemSlash(
        stemRightX: OrnamentLayout.graceStemRightX(
          graceLeftX: graceLeft,
          space: space,
        ),
        stemTipY: tipY,
        space: space,
      );
      canvas.drawLine(
        slash.from,
        slash.to,
        Paint()
          ..color = color
          ..strokeWidth = slash.width
          ..strokeCap = StrokeCap.butt,
      );
    }
  }

  /// Arpeggio wiggles and glissando lines. [xOf] gives the notehead x of a
  /// note index; the chord is every note of the same hand at the same beat.
  void _drawArpeggiosAndGlissandi(
    Canvas canvas, {
    required ({double space, double trebleBottomY, double bassTopY}) l,
    required double glyphSize,
    required Color color,
    required double Function(int index) xOf,
  }) {
    final space = l.space;
    bool onBassOf(bool leftHand) =>
        staves == Staves.grand ? leftHand : staves == Staves.bass;

    List<int> chordAt(double beat, bool leftHand) {
      final out = <int>[];
      var i = lowerBound(notes, beat - 1e-6);
      while (i < notes.length && (notes[i].beat - beat).abs() < 1e-6) {
        final n = notes[i];
        if (n.leftHand == leftHand && !n.isRest && !n.isSpacer) out.add(i);
        i++;
      }
      return out;
    }

    for (final a in arpeggios) {
      final idx = chordAt(a.beat, a.leftHand);
      if (idx.isEmpty) continue;
      final onBass = onBassOf(a.leftHand);
      final pitches = [for (final i in idx) notes[i].pitch];
      final hiPitch = pitches.reduce((p, q) => p > q ? p : q);
      final loPitch = pitches.reduce((p, q) => p < q ? p : q);
      // Staff line indices as MuseScore counts them (0 = top staff line).
      final topStep = diatonicStep(onBass ? 57 : 77); // A3 bass, F5 treble
      final v = ArpeggioLayout.verticalBounds(
        highestHeadY: _noteY(hiPitch, onBass, l),
        lowestHeadY: _noteY(loPitch, onBass, l),
        topLine: ArpeggioLayout.staffLine(
          step: diatonicStep(hiPitch),
          topLineStep: topStep,
        ),
        bottomLine: ArpeggioLayout.staffLine(
          step: diatonicStep(loPitch),
          topLineStep: topStep,
        ),
        space: space,
      );
      final heads = [
        for (final i in idx)
          (headX: xOf(i), hasAccidental: notes[i].accidental != null),
      ];
      final glyphs = ArpeggioLayout.layoutGlyphs(
        direction: a.direction,
        top: v.top,
        bottom: v.bottom,
        rightEdge: ArpeggioLayout.rightEdge(notes: heads, space: space),
        space: space,
      );
      for (final g in glyphs) {
        // Glyphs are rotated about their baseline-left origin (tlayout.cpp
        // "string is rotated -90 degrees" / "+90 degrees").
        canvas.save();
        canvas.translate(g.origin.dx, g.origin.dy);
        canvas.rotate(g.angle);
        _drawGlyph(canvas, g.glyph, glyphSize, Offset.zero, color);
        canvas.restore();
      }
    }

    for (final g in glissandi) {
      final starts = chordAt(g.startBeat, g.leftHand);
      final ends = chordAt(g.endBeat, g.leftHand);
      final pair = ArpeggioLayout.closestPair(
        [for (final i in starts) notes[i].pitch],
        [for (final i in ends) notes[i].pitch],
      );
      if (pair == null) continue;
      final si = starts[pair.$1];
      final ei = ends[pair.$2];
      final onBass = onBassOf(g.leftHand);
      final seg = ArpeggioLayout.glissandoEnds(
        startHead: Offset(xOf(si), _noteY(notes[si].pitch, onBass, l)),
        endHead: Offset(xOf(ei), _noteY(notes[ei].pitch, onBass, l)),
        space: space,
      );
      if (seg == null) continue;
      canvas.drawLine(
        seg.from,
        seg.to,
        Paint()
          ..color = color
          ..strokeWidth = math.max(1.0, ArpeggioLayout.glissandoWidthSp * space)
          ..strokeCap = StrokeCap.round,
      );
      final label = TextPainter(
        text: TextSpan(
          text: ArpeggioLayout.glissandoLabel,
          style: TextStyle(
            fontStyle: FontStyle.italic,
            fontSize: space * 1.3,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final c = ArpeggioLayout.glissandoLabelCentre(
        from: seg.from,
        to: seg.to,
        space: space,
      );
      label.paint(canvas, c - Offset(label.width / 2, label.height / 2));
    }
  }

  /// Draws a SMuFL glyph with its baseline origin at [origin].
  /// True when a note of [leftHand] sits on the bass staff (same rule as
  /// [_onBass], for a hand instead of a note).
  bool _ottavaOnBass(bool leftHand) => switch (staves) {
    Staves.treble => false,
    Staves.bass => true,
    Staves.grand => leftHand,
  };

  /// Ottava lines (`OttavaLayout`): a dashed line above the staff for `8va`
  /// and below it for `8vb`, with a hook at its right end. Spans run from
  /// the note at the start beat to the note at the end beat ([xAt]).
  /// The hook is drawn solid: see [OttavaLayout.dashSpans].
  void _drawOttavas(
    Canvas canvas,
    ({double space, double trebleBottomY, double bassTopY}) l,
    double Function(double beat) xAt,
    Color color,
  ) {
    final space = l.space;
    final paint = Paint()
      ..color = color
      ..strokeWidth = OttavaLayout.lineWidthSp * space
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    for (final o in ottavas) {
      final x1 = xAt(o.startBeat);
      final x2 = xAt(o.endBeat);
      if (x2 <= x1) continue;
      final onBass = _ottavaOnBass(o.leftHand);
      final staffTop = onBass ? l.bassTopY : l.trebleBottomY - 4 * space;
      final staffBottom = onBass ? l.bassTopY + 4 * space : l.trebleBottomY;
      final y = OttavaLayout.lineY(
        kind: o.kind,
        staffTop: staffTop,
        staffBottom: staffBottom,
        space: space,
      );
      for (final s in OttavaLayout.dashSpans(length: x2 - x1, space: space)) {
        canvas.drawLine(Offset(x1 + s.from, y), Offset(x1 + s.to, y), paint);
      }
      final hookY = OttavaLayout.hookEndY(kind: o.kind, lineY: y, space: space);
      canvas.drawLine(Offset(x2, y), Offset(x2, hookY), paint);
    }
  }

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
      old.dynamics != dynamics ||
      old.hairpins != hairpins ||
      old.ottavas != ottavas ||
      old.repeatBarlines != repeatBarlines ||
      old.voltas != voltas ||
      old.navigation != navigation ||
      old.ornaments != ornaments ||
      old.acciaccaturas != acciaccaturas ||
      old.chords != chords ||
      old.lyrics != lyrics ||
      old.pixelsPerBeat != pixelsPerBeat;
}

/// A lyric item placed for drawing on its hand's row (see
/// `StaffPainter._drawChordsAndLyrics`).
class _LyricSlot {
  _LyricSlot(
    this.lyric, {
    required this.centre,
    required this.width,
    required this.headRight,
  });

  final StaffLyric lyric;

  /// Centre of the notehead it sits under.
  final double centre;

  /// Text width; zero for an extension.
  final double width;

  /// Right edge of the notehead it sits under (melisma end).
  final double headRight;

  /// Top of the row, and its baseline. Set once the row is laid out.
  double boxTop = 0;
  double baseline = 0;

  double get left => HarmonyLayout.lyricLeft(centreX: centre, width: width);
  double get right => left + width;
}
