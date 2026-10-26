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

  double scoreX = 0.0;
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

  /// MuseScore non-linear duration stretch (HorizontalSpacing::durationStretchForTicks).
  ///
  /// durStretch = pow(slope, log2(durationRatio)) where reference duration = 1.0 (quarter note).
  static double durationStretch(double beats, {double slope = 1.5}) {
    if (beats <= 0) return 0.0;
    return math.pow(slope, math.log(beats) / math.ln2).toDouble();
  }

  /// Builds segments for all notes and computes their unified horizontal X coordinates.
  static List<SegmentInfo> buildSegments({
    required List<StaffNote> notes,
    required double anchorX,
    required double nowBeat,
    required double pixelsPerBeat,
    required double space,
    required double? beatsPerBar,
    required Map<int, AccidentalType> noteAccidentals,
    List<double> measureStarts = const [],
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

    // 1. Compute cumulative scoreX for each segment based on MuseScore's duration
    // stretch and padding clearances.
    for (var k = 0; k < segments.length; k++) {
      final seg = segments[k];
      if (k == 0) {
        seg.scoreX = 0.0;
      } else {
        final prev = segments[k - 1];
        final deltaBeats = seg.beat - prev.beat;
        final bool crossedBar = measureStarts.isNotEmpty
            ? measureStarts.any(
                (beat) => beat > prev.beat + 1e-6 && beat <= seg.beat + 1e-6,
              )
            : beatsPerBar != null &&
                  beatsPerBar > 0 &&
                  ((seg.beat / beatsPerBar).floor() >
                      (prev.beat / beatsPerBar).floor());

        // Non-linear duration stretch (quarter note = 1.0 stretch, eighth = 0.667 stretch, 16th = 0.444 stretch)
        final nominalSpacing = durationStretch(deltaBeats) * pixelsPerBeat;

        // MuseScore paddingtable.cpp clearances
        final double minGap;
        if (crossedBar) {
          minGap = seg.hasAccidental ? space * 3.2 : space * 2.2;
        } else {
          minGap = seg.hasAccidental ? space * 1.8 : space * 0.45;
        }

        final minSpacing =
            prev.rightWidth * space + minGap + seg.leftOffset * space;
        seg.scoreX = prev.scoreX + math.max(nominalSpacing, minSpacing);
      }
    }

    // 2. Map nowBeat to score coordinate and position segments relative to anchorX
    double scoreXAtBeat(double beat) {
      if (segments.isEmpty) return 0.0;
      if (beat <= segments.first.beat) {
        return segments.first.scoreX +
            (beat - segments.first.beat) * pixelsPerBeat;
      }
      if (beat >= segments.last.beat) {
        return segments.last.scoreX +
            (beat - segments.last.beat) * pixelsPerBeat;
      }
      var low = 0;
      var high = segments.length - 1;
      while (low <= high) {
        final mid = (low + high) ~/ 2;
        if (segments[mid].beat <= beat) {
          if (mid + 1 < segments.length && segments[mid + 1].beat > beat) {
            final b0 = segments[mid].beat;
            final b1 = segments[mid + 1].beat;
            final x0 = segments[mid].scoreX;
            final x1 = segments[mid + 1].scoreX;
            final t = (beat - b0) / (b1 - b0);
            return x0 + t * (x1 - x0);
          }
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }
      return segments.first.scoreX;
    }

    final nowScoreX = scoreXAtBeat(nowBeat);
    for (final seg in segments) {
      seg.x = anchorX + (seg.scoreX - nowScoreX);
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
    if (segments.isEmpty) {
      return anchorX + (barBeat - nowBeat) * pixelsPerBeat - space * 0.8;
    }
    double scoreXAtBeat(double beat) {
      if (beat <= segments.first.beat) {
        return segments.first.scoreX +
            (beat - segments.first.beat) * pixelsPerBeat;
      }
      if (beat >= segments.last.beat) {
        return segments.last.scoreX +
            (beat - segments.last.beat) * pixelsPerBeat;
      }
      var low = 0;
      var high = segments.length - 1;
      while (low <= high) {
        final mid = (low + high) ~/ 2;
        if (segments[mid].beat <= beat) {
          if (mid + 1 < segments.length && segments[mid + 1].beat > beat) {
            final b0 = segments[mid].beat;
            final b1 = segments[mid + 1].beat;
            final x0 = segments[mid].scoreX;
            final x1 = segments[mid + 1].scoreX;
            final t = (beat - b0) / (b1 - b0);
            return x0 + t * (x1 - x0);
          }
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }
      return segments.first.scoreX;
    }

    final nowScoreX = scoreXAtBeat(nowBeat);
    final barScoreX = scoreXAtBeat(barBeat);
    final barX = anchorX + (barScoreX - nowScoreX);

    SegmentInfo? prevSeg;
    SegmentInfo? nextSeg;
    for (final seg in segments) {
      if (seg.beat < barBeat - 1e-4) {
        prevSeg = seg;
      } else if (seg.beat >= barBeat - 1e-4 && nextSeg == null) {
        nextSeg = seg;
      }
    }

    final rightBoundary = nextSeg != null
        ? (nextSeg.x - nextSeg.leftOffset * space)
        : barX;
    final nominalBx = rightBoundary - space * 0.8;

    if (prevSeg != null) {
      final prevRight = prevSeg.x + prevSeg.rightWidth * space;
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
}
