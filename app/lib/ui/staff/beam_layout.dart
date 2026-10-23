import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'staff_note.dart';

/// A group of notes connected by beam bars (MuseScore beamlayout.cpp style).
class BeamGroup {
  BeamGroup({
    required this.indices,
    required this.stemDown,
    required this.slope,
    required this.baseY,
    required this.firstSx,
    required this.stemXs,
  });

  /// Indices of notes in the group (at least 2).
  final List<int> indices;

  /// Unified stem direction for all notes in this group.
  final bool stemDown;

  /// Vertical slope of the beam (delta Y / delta X).
  final double slope;

  /// Vertical position of the beam at [firstSx].
  final double baseY;

  /// Stem X coordinate of the first note.
  final double firstSx;

  /// Stem X coordinate for each note index in [indices].
  final Map<int, double> stemXs;

  /// Computes beam Y at [sx].
  double beamY(double sx) => baseY + slope * (sx - firstSx);
}

/// Computes and renders beams for eighth and sixteenth notes.
abstract final class BeamLayout {
  /// Identifies and constructs [BeamGroup]s for consecutive subdivision notes
  /// (beats <= 0.5) within the same metric beat and staff.
  static List<BeamGroup> computeBeamGroups({
    required List<StaffNote> notes,
    required int first,
    required double lastBeat,
    required bool Function(StaffNote) onBass,
    required double Function(int pitch, bool onBass) noteY,
    required Map<int, double> noteXs,
    required double space,
    required double? beatsPerBar,
  }) {
    final groups = <BeamGroup>[];
    final bpb = beatsPerBar ?? 4.0;

    int beatGroupOf(double b) => (bpb == 6 ? (b / 1.5) : b).floor();
    int barOf(double b) => bpb > 0 ? (b / bpb).floor() : 0;

    var currentGroup = <int>[];

    void finishGroup() {
      if (currentGroup.length >= 2) {
        final indices = List<int>.from(currentGroup);
        final firstIdx = indices.first;
        final onB = onBass(notes[firstIdx]);
        final midPitch = onB ? 50 : 71; // D3 on bass, B4 on treble

        var downVotes = 0;
        for (final idx in indices) {
          if (notes[idx].pitch > midPitch) {
            downVotes++;
          } else if (notes[idx].pitch < midPitch) {
            downVotes--;
          }
        }
        final stemDown = downVotes > 0;

        final stemXs = <int, double>{};
        final strokeWidth = math.max(1.2, space * 0.1);
        for (final idx in indices) {
          final x = noteXs[idx] ?? 0;
          stemXs[idx] = stemDown
              ? x + strokeWidth / 2
              : x + space * 1.3 - strokeWidth / 2;
        }

        final firstSx = stemXs[indices.first]!;
        final lastSx = stemXs[indices.last]!;
        final firstNy = noteY(notes[indices.first].pitch, onB);
        final lastNy = noteY(notes[indices.last].pitch, onB);

        final tipY0 = stemDown ? firstNy + space * 3.2 : firstNy - space * 3.2;
        final tipYLast = stemDown ? lastNy + space * 3.2 : lastNy - space * 3.2;

        final dx = lastSx - firstSx;
        var slope = 0.0;
        if (dx > 1e-4) {
          final rawSlope = (tipYLast - tipY0) / dx;
          // MuseScore: clamp slope so beam never slopes by more than 0.8 staff space.
          final maxSlope = (space * 0.8) / dx;
          slope = rawSlope.clamp(-maxSlope, maxSlope);
        }

        var baseY = tipY0;
        double beamY(double sx) => baseY + slope * (sx - firstSx);

        // Adjust baseY so every stem meets the minimum required length (3.0 spaces).
        if (!stemDown) {
          var minLen = 1e9;
          for (final idx in indices) {
            final ny = noteY(notes[idx].pitch, onB);
            final len = ny - beamY(stemXs[idx]!);
            if (len < minLen) minLen = len;
          }
          if (minLen < space * 3.0) {
            baseY -= (space * 3.0 - minLen);
          }
        } else {
          var minLen = 1e9;
          for (final idx in indices) {
            final ny = noteY(notes[idx].pitch, onB);
            final len = beamY(stemXs[idx]!) - ny;
            if (len < minLen) minLen = len;
          }
          if (minLen < space * 3.0) {
            baseY += (space * 3.0 - minLen);
          }
        }

        groups.add(
          BeamGroup(
            indices: indices,
            stemDown: stemDown,
            slope: slope,
            baseY: baseY,
            firstSx: firstSx,
            stemXs: stemXs,
          ),
        );
      }
      currentGroup = [];
    }

    for (var i = math.max(0, first - 4); i < notes.length; i++) {
      final n = notes[i];
      if (n.beat > lastBeat + 2.0) break;
      if (n.isRest || n.isSpacer || n.beats > 0.5) {
        finishGroup();
        continue;
      }

      if (currentGroup.isEmpty) {
        currentGroup.add(i);
      } else {
        final prevIdx = currentGroup.last;
        final prev = notes[prevIdx];
        if ((n.beat - prev.beat).abs() < 1e-6) {
          // Chord note: shares onset beat, handled as chord
          continue;
        }
        final sameBar = barOf(n.beat) == barOf(prev.beat);
        final sameBeat = beatGroupOf(n.beat) == beatGroupOf(prev.beat);
        final sameStaff = onBass(n) == onBass(prev);
        final sameHand = n.leftHand == prev.leftHand;
        final contiguous = (n.beat - (prev.beat + prev.beats)).abs() < 1e-4;

        if (sameBar && sameBeat && sameStaff && sameHand && contiguous) {
          currentGroup.add(i);
        } else {
          finishGroup();
          currentGroup.add(i);
        }
      }
    }
    finishGroup();
    return groups;
  }

  /// Draws the stems, primary beam, and secondary beam(s) for a [BeamGroup].
  static void drawBeamGroup({
    required Canvas canvas,
    required BeamGroup group,
    required List<StaffNote> notes,
    required double Function(int pitch, bool onBass) noteY,
    required bool Function(StaffNote) onBass,
    required double space,
    required Color defaultColor,
    required Color Function(int index)? colorOf,
  }) {
    final strokePaint = Paint()
      ..color = defaultColor
      ..strokeWidth = math.max(1.2, space * 0.1);
    final beamPaint = Paint()
      ..color = defaultColor
      ..style = PaintingStyle.fill;
    final t = space * 0.48;

    // Draw stems for all notes in the beam group
    for (final idx in group.indices) {
      final sx = group.stemXs[idx]!;
      final n = notes[idx];
      final ny = noteY(n.pitch, onBass(n));
      final by = group.beamY(sx);
      final c = colorOf?.call(idx) ?? defaultColor;
      canvas.drawLine(
        Offset(sx, ny),
        Offset(sx, by),
        Paint()
          ..color = c
          ..strokeWidth = strokePaint.strokeWidth,
      );
    }

    // Draw primary beam connecting first and last stem
    final firstSx = group.stemXs[group.indices.first]!;
    final lastSx = group.stemXs[group.indices.last]!;
    final by1 = group.beamY(firstSx);
    final by2 = group.beamY(lastSx);

    final p = Path();
    if (!group.stemDown) {
      p.moveTo(firstSx, by1);
      p.lineTo(lastSx, by2);
      p.lineTo(lastSx, by2 + t);
      p.lineTo(firstSx, by1 + t);
    } else {
      p.moveTo(firstSx, by1);
      p.lineTo(lastSx, by2);
      p.lineTo(lastSx, by2 - t);
      p.lineTo(firstSx, by1 - t);
    }
    p.close();
    canvas.drawPath(p, beamPaint);

    // Draw secondary beam(s) for 16th notes (beats <= 0.25)
    final s = space * 0.72;
    var secStart = -1;
    for (var k = 0; k < group.indices.length; k++) {
      final idx = group.indices[k];
      final is16th = notes[idx].beats <= 0.25;
      if (is16th) {
        if (secStart == -1) secStart = k;
      } else {
        if (secStart != -1) {
          _drawSecondaryBeam(
            canvas: canvas,
            group: group,
            startK: secStart,
            endK: k - 1,
            s: s,
            t: t,
            paint: beamPaint,
            space: space,
          );
          secStart = -1;
        }
      }
    }
    if (secStart != -1) {
      _drawSecondaryBeam(
        canvas: canvas,
        group: group,
        startK: secStart,
        endK: group.indices.length - 1,
        s: s,
        t: t,
        paint: beamPaint,
        space: space,
      );
    }
  }

  static void _drawSecondaryBeam({
    required Canvas canvas,
    required BeamGroup group,
    required int startK,
    required int endK,
    required double s,
    required double t,
    required Paint paint,
    required double space,
  }) {
    double sxA, sxB;
    if (startK == endK) {
      final sx = group.stemXs[group.indices[startK]]!;
      final beamletLen = space * 0.9;
      if (startK == 0) {
        sxA = sx;
        sxB = sx + beamletLen;
      } else {
        sxA = sx - beamletLen;
        sxB = sx;
      }
    } else {
      sxA = group.stemXs[group.indices[startK]]!;
      sxB = group.stemXs[group.indices[endK]]!;
    }

    final byA = group.beamY(sxA);
    final byB = group.beamY(sxB);
    final p = Path();
    if (!group.stemDown) {
      p.moveTo(sxA, byA + s);
      p.lineTo(sxB, byB + s);
      p.lineTo(sxB, byB + s + t);
      p.lineTo(sxA, byA + s + t);
    } else {
      p.moveTo(sxA, byA - s);
      p.lineTo(sxB, byB - s);
      p.lineTo(sxB, byB - s - t);
      p.lineTo(sxA, byA - s - t);
    }
    p.close();
    canvas.drawPath(p, paint);
  }
}
