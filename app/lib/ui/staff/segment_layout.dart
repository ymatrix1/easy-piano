import 'dart:math' as math;

import 'key_signature.dart';
import 'staff_note.dart';

/// Information about a single horizontal musical time slice (MuseScore `Segment`).
class SegmentInfo {
  SegmentInfo({
    required this.beat,
    required this.noteIndices,
    required this.hasAccidental,
    required this.hasDot,
    required this.maxHeadWidth,
  });

  final double beat;
  final List<int> noteIndices;
  final bool hasAccidental;
  final bool hasDot;
  final double maxHeadWidth;

  double x = 0.0;
  double get leftOffset => hasAccidental ? 1.4 : 0.0;
  double get rightWidth => hasDot ? maxHeadWidth + 0.65 : maxHeadWidth;
}

/// Implements MuseScore's Segment & Horizontal Spacing layout (`segmentlayout.cpp`, `horizontalspacing.cpp`).
abstract final class SegmentLayout {
  static bool _isDotted(double beats) =>
      (beats - 1.5).abs() < 1e-4 ||
      (beats - 3.0).abs() < 1e-4 ||
      (beats - 0.75).abs() < 1e-4 ||
      (beats - 0.375).abs() < 1e-4;

  /// Builds segments for all notes and computes their unified horizontal X coordinates.
  static List<SegmentInfo> buildSegments({
    required List<StaffNote> notes,
    required double anchorX,
    required double nowBeat,
    required double pixelsPerBeat,
    required double space,
    required double? beatsPerBar,
    required Map<int, AccidentalType> noteAccidentals,
  }) {
    final segmentsByBeat = <double, List<int>>{};
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      if (n.isSpacer) continue;
      // Round to 1e-4 for numerical stability
      final b = (n.beat * 10000).round() / 10000;
      segmentsByBeat.putIfAbsent(b, () => []).add(i);
    }

    final sortedBeats = segmentsByBeat.keys.toList()..sort();
    final segments = <SegmentInfo>[];
    for (final b in sortedBeats) {
      final indices = segmentsByBeat[b]!;
      var hasAccidental = false;
      var hasDot = false;
      var maxHeadW = 0.0;

      for (final idx in indices) {
        final n = notes[idx];
        if (noteAccidentals.containsKey(idx)) {
          hasAccidental = true;
        }
        if (_isDotted(n.beats)) {
          hasDot = true;
        }
        final double hw = n.isRest ? 1.0 : (n.beats >= 4.0 ? 1.5 : 1.3);
        if (hw > maxHeadW) maxHeadW = hw;
      }
      if (maxHeadW == 0.0) maxHeadW = 1.3;

      segments.add(
        SegmentInfo(
          beat: b,
          noteIndices: indices,
          hasAccidental: hasAccidental,
          hasDot: hasDot,
          maxHeadWidth: maxHeadW,
        ),
      );
    }

    // Compute unified X positions for each segment
    for (var k = 0; k < segments.length; k++) {
      final seg = segments[k];
      final nominalX = anchorX + (seg.beat - nowBeat) * pixelsPerBeat;
      if (k == 0) {
        seg.x = nominalX;
      } else {
        final prev = segments[k - 1];
        final bool crossedBar =
            beatsPerBar != null &&
            beatsPerBar > 0 &&
            ((seg.beat / beatsPerBar).floor() >
                (prev.beat / beatsPerBar).floor());

        final double minGap;
        if (crossedBar) {
          minGap = seg.hasAccidental ? space * 2.8 : space * 1.8;
        } else {
          minGap = seg.hasAccidental ? space * 1.6 : space * 0.4;
        }

        final minX =
            prev.x + prev.rightWidth * space + minGap + seg.leftOffset * space;
        seg.x = math.max(nominalX, minX);
      }
    }

    return segments;
  }

  /// Maps every note index to its segment's horizontal X position.
  static Map<int, double> computeNoteXs(List<SegmentInfo> segments) {
    final xCache = <int, double>{};
    for (final seg in segments) {
      for (final idx in seg.noteIndices) {
        xCache[idx] = seg.x;
      }
    }
    return xCache;
  }

  /// Computes the horizontal position of a barline ensuring clean spacing
  /// between the preceding and following segments (MuseScore `MeasureLayout`).
  static double barLineX({
    required double barBeat,
    required double nowBeat,
    required double anchorX,
    required double pixelsPerBeat,
    required double space,
    required List<SegmentInfo> segments,
  }) {
    final nominalX = anchorX + (barBeat - nowBeat) * pixelsPerBeat;
    SegmentInfo? prevSeg;
    SegmentInfo? nextSeg;
    for (final seg in segments) {
      if (seg.beat < barBeat - 1e-4) {
        prevSeg = seg;
      } else if (seg.beat >= barBeat - 1e-4 && nextSeg == null) {
        nextSeg = seg;
      }
    }

    var result = nominalX;
    if (prevSeg != null) {
      final minBarX = prevSeg.x + prevSeg.rightWidth * space + space * 0.8;
      if (result < minBarX) {
        result = minBarX;
      }
    }
    if (nextSeg != null) {
      final maxBarX = nextSeg.x - nextSeg.leftOffset * space - space * 0.8;
      if (result > maxBarX && prevSeg != null) {
        result =
            (prevSeg.x +
                prevSeg.rightWidth * space +
                nextSeg.x -
                nextSeg.leftOffset * space) /
            2;
      }
    }
    return result;
  }
}
