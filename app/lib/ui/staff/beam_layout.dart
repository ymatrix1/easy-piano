import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'staff_note.dart';
import 'stem_layout.dart';

/// A group of notes connected by beam bars (MuseScore beamlayout.cpp style).
class BeamGroup {
  BeamGroup({
    required this.allIndices,
    required this.chords,
    required this.stemDown,
    required this.slope,
    required this.baseY,
    required this.firstSx,
    required this.stemXs,
  });

  /// All note indices that are part of this beam group (for [beamedIndices] suppression).
  final List<int> allIndices;

  /// The list of chords (each chord is a list of note indices sharing the same onset beat).
  final List<List<int>> chords;

  /// Representative primary indices (first note of each chord).
  List<int> get indices => [for (final c in chords) c.first];

  final bool stemDown;
  final double slope;
  final double baseY;
  final double firstSx;
  final Map<int, double> stemXs;

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
    final bpb = beatsPerBar ?? 4.0;

    // MuseScore beamlayout.cpp: each track/staff is computed independently.
    final trebleIndices = <int>[];
    final bassIndices = <int>[];

    for (var i = math.max(0, first - 8); i < notes.length; i++) {
      final n = notes[i];
      if (n.beat > lastBeat + 2.0) break;
      if (onBass(n)) {
        bassIndices.add(i);
      } else {
        trebleIndices.add(i);
      }
    }

    final groups = <BeamGroup>[];
    groups.addAll(
      _computeBeamGroupsForStaff(
        staffIndices: trebleIndices,
        isBass: false,
        notes: notes,
        noteY: noteY,
        noteXs: noteXs,
        space: space,
        bpb: bpb,
      ),
    );
    groups.addAll(
      _computeBeamGroupsForStaff(
        staffIndices: bassIndices,
        isBass: true,
        notes: notes,
        noteY: noteY,
        noteXs: noteXs,
        space: space,
        bpb: bpb,
      ),
    );

    return groups;
  }

  static List<BeamGroup> _computeBeamGroupsForStaff({
    required List<int> staffIndices,
    required bool isBass,
    required List<StaffNote> notes,
    required double Function(int pitch, bool onBass) noteY,
    required Map<int, double> noteXs,
    required double space,
    required double bpb,
  }) {
    final groups = <BeamGroup>[];
    int beatGroupOf(double b) => (bpb == 6 ? (b / 1.5) : b).floor();
    int barOf(double b) => bpb > 0 ? (b / bpb).floor() : 0;

    // Group staff indices into chords by onset beat
    final chords = <List<int>>[];
    for (final idx in staffIndices) {
      final n = notes[idx];
      if (chords.isNotEmpty &&
          (n.beat - notes[chords.last.first].beat).abs() < 1e-6) {
        chords.last.add(idx);
      } else {
        chords.add([idx]);
      }
    }

    var currentChords = <List<int>>[];

    void finishGroup() {
      if (currentChords.length >= 2) {
        // Vote stem direction across chords in group.
        // In grand staff, bass stems point DOWN to keep the inter-staff space clean (Gould / MuseScore).
        var downVotes = isBass ? 2 : 0;
        for (final c in currentChords) {
          for (final idx in c) {
            if (notes[idx].isStemDown(isBass)) {
              downVotes++;
            } else {
              downVotes--;
            }
          }
        }
        final stemDown = isBass || downVotes >= 0;

        final stemXs = <int, double>{};
        for (final c in currentChords) {
          final primaryIdx = c.first;
          final x = noteXs[primaryIdx] ?? 0;
          stemXs[primaryIdx] = StemLayout.stemX(
            noteheadX: x,
            stemDown: stemDown,
            space: space,
          );
        }

        final firstPrimary = currentChords.first.first;
        final lastPrimary = currentChords.last.first;
        final firstSx = stemXs[firstPrimary]!;
        final lastSx = stemXs[lastPrimary]!;

        int extremePitch(List<int> c, bool stemDown) {
          var best = notes[c.first].pitch;
          for (final idx in c) {
            final p = notes[idx].pitch;
            if (stemDown ? (p < best) : (p > best)) best = p;
          }
          return best;
        }

        final firstNy = noteY(
          extremePitch(currentChords.first, stemDown),
          isBass,
        );
        final lastNy = noteY(
          extremePitch(currentChords.last, stemDown),
          isBass,
        );

        final tipY0 = stemDown ? firstNy + space * 3.2 : firstNy - space * 3.2;
        final tipYLast = stemDown ? lastNy + space * 3.2 : lastNy - space * 3.2;

        final dx = lastSx - firstSx;
        var slope = 0.0;
        if (dx > 1e-4) {
          final rawSlope = (tipYLast - tipY0) / dx;
          final maxSlope = (space * 0.8) / dx;
          slope = rawSlope.clamp(-maxSlope, maxSlope);
        }

        var baseY = tipY0;
        double beamY(double sx) => baseY + slope * (sx - firstSx);

        // Adjust baseY so every stem meets the minimum required length (3.0 spaces).
        if (!stemDown) {
          var minLen = 1e9;
          for (final c in currentChords) {
            final primaryIdx = c.first;
            final ny = noteY(extremePitch(c, stemDown), isBass);
            final len = ny - beamY(stemXs[primaryIdx]!);
            if (len < minLen) minLen = len;
          }
          if (minLen < space * 3.0) {
            baseY -= (space * 3.0 - minLen);
          }
        } else {
          var minLen = 1e9;
          for (final c in currentChords) {
            final primaryIdx = c.first;
            final ny = noteY(extremePitch(c, stemDown), isBass);
            final len = beamY(stemXs[primaryIdx]!) - ny;
            if (len < minLen) minLen = len;
          }
          if (minLen < space * 3.0) {
            baseY += (space * 3.0 - minLen);
          }
        }

        final allIndices = [for (final c in currentChords) ...c];
        groups.add(
          BeamGroup(
            allIndices: allIndices,
            chords: List.from(currentChords),
            stemDown: stemDown,
            slope: slope,
            baseY: baseY,
            firstSx: firstSx,
            stemXs: stemXs,
          ),
        );
      }
      currentChords = [];
    }

    for (final c in chords) {
      final primary = notes[c.first];
      if (primary.isRest || primary.isSpacer || primary.beats > 0.5) {
        finishGroup();
        continue;
      }

      if (currentChords.isEmpty) {
        currentChords.add(c);
      } else {
        final prev = notes[currentChords.last.first];
        final sameBar = barOf(primary.beat) == barOf(prev.beat);
        final isEighthOnly =
            (primary.beats - 0.5).abs() < 1e-4 &&
            (prev.beats - 0.5).abs() < 1e-4;
        final bool sameMetricUnit;
        if (bpb == 4.0 && isEighthOnly) {
          // Half-measure beaming for eighths in 4/4 (Gould / MuseScore rule)
          sameMetricUnit =
              (primary.beat / 2.0).floor() == (prev.beat / 2.0).floor();
        } else {
          sameMetricUnit = beatGroupOf(primary.beat) == beatGroupOf(prev.beat);
        }
        final contiguous =
            (primary.beat - (prev.beat + prev.beats)).abs() < 1e-4;

        if (sameBar && sameMetricUnit && contiguous) {
          currentChords.add(c);
        } else {
          finishGroup();
          currentChords.add(c);
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

    // Draw stems for all chords in the beam group
    for (final c in group.chords) {
      final primaryIdx = c.first;
      final sx = group.stemXs[primaryIdx]!;

      var chordLowestY = -1e9;
      var chordHighestY = 1e9;
      for (final idx in c) {
        final ny = noteY(notes[idx].pitch, onBass(notes[idx]));
        if (ny > chordLowestY) {
          chordLowestY = ny; // lowest pitch (highest canvas Y)
        }
        if (ny < chordHighestY) {
          chordHighestY = ny; // highest pitch (lowest canvas Y)
        }
      }

      final by = group.beamY(sx);
      final cColor = colorOf?.call(primaryIdx) ?? defaultColor;
      final startY = group.stemDown ? chordHighestY : chordLowestY;
      canvas.drawLine(
        Offset(sx, startY),
        Offset(sx, by),
        Paint()
          ..color = cColor
          ..strokeWidth = strokePaint.strokeWidth,
      );
    }

    // Draw primary beam connecting first and last stem
    final firstPrimary = group.chords.first.first;
    final lastPrimary = group.chords.last.first;
    final firstSx = group.stemXs[firstPrimary]!;
    final lastSx = group.stemXs[lastPrimary]!;
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
    for (var k = 0; k < group.chords.length; k++) {
      final primaryIdx = group.chords[k].first;
      final is16th = notes[primaryIdx].beats <= 0.25;
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
        endK: group.chords.length - 1,
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
      final sx = group.stemXs[group.chords[startK].first]!;
      final beamletLen = space * 0.9;
      if (startK == 0) {
        sxA = sx;
        sxB = sx + beamletLen;
      } else {
        sxA = sx - beamletLen;
        sxB = sx;
      }
    } else {
      sxA = group.stemXs[group.chords[startK].first]!;
      sxB = group.stemXs[group.chords[endK].first]!;
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
