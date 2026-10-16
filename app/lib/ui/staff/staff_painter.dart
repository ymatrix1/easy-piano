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

/// Scrolling grand staff: notes move right to left toward a fixed playhead.
/// Only notes inside the visible beat window are laid out and painted.
class StaffPainter extends CustomPainter {
  StaffPainter({
    required this.notes,
    required this.playheadBeat,
    required this.inkColor,
    required this.playheadColor,
    this.pixelsPerBeat = 90,
  }) : super(repaint: playheadBeat);

  final List<StaffNote> notes;
  final ValueNotifier<double> playheadBeat;
  final Color inkColor;
  final Color playheadColor;
  final double pixelsPerBeat;

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

  TextPainter _glyph(String g, double size) {
    return _glyphCache.putIfAbsent('$g@$size', () {
      return TextPainter(
        text: TextSpan(
          text: g,
          style: TextStyle(
            fontFamily: 'Bravura',
            fontSize: size,
            color: inkColor,
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

  @override
  void paint(Canvas canvas, Size size) {
    final space = (size.height / 16).clamp(
      6.0,
      14.0,
    ); // distance between staff lines
    final half = space / 2;
    final glyphSize = space * 4; // SMuFL: 1 em = 4 staff spaces
    final trebleBottomY = size.height * 0.42;
    final bassTopY = trebleBottomY + space * 4;
    final playheadX = size.width * 0.22;
    final ink = Paint()
      ..color = inkColor
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
    );
    _drawGlyph(canvas, Smufl.fClef, glyphSize, Offset(8, bassTopY + space));

    // Visible window in beats.
    final now = playheadBeat.value;
    final firstBeat = now - playheadX / pixelsPerBeat - 4;
    final lastBeat = now + (size.width - playheadX) / pixelsPerBeat;
    for (var i = _lowerBound(firstBeat); i < notes.length; i++) {
      final n = notes[i];
      if (n.beat > lastBeat) break;
      final x = playheadX + (n.beat - now) * pixelsPerBeat;
      if (x < 60) continue; // behind the clefs
      final step = diatonicStep(n.pitch);
      final y = n.leftHand
          ? bassTopY + (_bassTopStep - step) * half
          : trebleBottomY - (step - _trebleBottomStep) * half;
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
      final head = n.beats >= 4
          ? Smufl.noteheadWhole
          : n.beats >= 2
          ? Smufl.noteheadHalf
          : Smufl.noteheadBlack;
      _drawGlyph(canvas, head, glyphSize, Offset(x, y));
      if (_isSharp[n.pitch % 12]) {
        _drawGlyph(
          canvas,
          Smufl.accidentalSharp,
          glyphSize,
          Offset(x - space * 1.4, y),
        );
      }
      if (n.beats < 4) {
        // Stem up from the right side of the notehead (1.18 spaces wide in Bravura).
        final sx = x + space * 1.18 - 0.6;
        canvas.drawLine(Offset(sx, y), Offset(sx, y - space * 3.5), ink);
      }
    }

    // Playhead.
    canvas.drawLine(
      Offset(playheadX, trebleBottomY - space * 6),
      Offset(playheadX, bassTopY + space * 6),
      Paint()
        ..color = playheadColor
        ..strokeWidth = 3,
    );
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
  void _drawGlyph(Canvas canvas, String g, double size, Offset origin) {
    final tp = _glyph(g, size);
    final baseline = tp.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    tp.paint(canvas, Offset(origin.dx, origin.dy - baseline));
  }

  @override
  bool shouldRepaint(StaffPainter old) =>
      old.notes != notes ||
      old.inkColor != inkColor ||
      old.pixelsPerBeat != pixelsPerBeat;
}
