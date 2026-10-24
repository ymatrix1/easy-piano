import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'smufl.dart';
import 'staff_note.dart';

/// Implements tuplet (e.g. triplet) grouping and bracket rendering following
/// MuseScore `tupletlayout.cpp` and Gould rules.
class TupletGroup {
  const TupletGroup({
    required this.indices,
    required this.number,
    required this.startX,
    required this.endX,
    required this.y,
    required this.isAbove,
    required this.hasBeam,
  });

  final List<int> indices;
  final int number;
  final double startX;
  final double endX;
  final double y;
  final bool isAbove;
  final bool hasBeam;
}

abstract final class TupletLayout {
  /// Finds tuplet groups in notes.
  static List<TupletGroup> computeTupletGroups({
    required List<StaffNote> notes,
    required int first,
    required double lastBeat,
    required Map<int, double> noteXs,
    required double Function(int pitch, bool onBass) noteY,
    required bool Function(StaffNote) onBass,
    required Set<int> beamedIndices,
    required double space,
    bool isGrandStaff = false,
  }) {
    final groups = <TupletGroup>[];
    var currentGroup = <int>[];
    int? currentTupletNum;

    void flush() {
      if (currentGroup.length >= 3 && currentTupletNum != null) {
        final indices = List<int>.from(currentGroup);
        final firstX = noteXs[indices.first] ?? 0.0;
        final lastX = noteXs[indices.last] ?? 0.0;

        // Check if all notes in group are beamed
        final allBeamed = indices.every(beamedIndices.contains);

        // Compute average Y
        var sumY = 0.0;
        for (final idx in indices) {
          sumY += noteY(notes[idx].pitch, onBass(notes[idx]));
        }
        final avgY = sumY / indices.length;

        // Place tuplet above or below based on stem direction (Gould: opposite stems)
        var downVotes = 0;
        for (final idx in indices) {
          if (notes[idx].isStemDown(
            onBass(notes[idx]),
            isGrandStaff: isGrandStaff,
          )) {
            downVotes++;
          } else {
            downVotes--;
          }
        }
        final isAbove = downVotes >= 0;
        final y = isAbove ? avgY - space * 3.8 : avgY + space * 3.8;

        groups.add(
          TupletGroup(
            indices: indices,
            number: currentTupletNum!,
            startX: firstX,
            endX: lastX + space * 1.2,
            y: y,
            isAbove: isAbove,
            hasBeam: allBeamed,
          ),
        );
      }
      currentGroup = [];
      currentTupletNum = null;
    }

    for (var i = first; i < notes.length; i++) {
      final n = notes[i];
      if (n.beat > lastBeat) break;
      if (n.isSpacer || n.isRest) {
        flush();
        continue;
      }

      if (n.tuplet != null) {
        if (currentTupletNum != null && currentTupletNum != n.tuplet) {
          flush();
        }
        currentTupletNum = n.tuplet;
        currentGroup.add(i);
        if (currentGroup.length == n.tuplet) {
          flush();
        }
      } else {
        flush();
      }
    }
    flush();

    return groups;
  }

  /// Renders tuplet bracket and number.
  static void drawTupletGroup({
    required Canvas canvas,
    required TupletGroup group,
    required double space,
    required Color color,
    required void Function(Canvas, String, double, Offset, Color) drawGlyph,
  }) {
    final numGlyph = Smufl.tupletDigitGlyph(group.number) ?? Smufl.tuplet3;
    final digitWidth = space * 0.9;
    final midX = (group.startX + group.endX) / 2;
    final textY = group.y;

    // Draw the number digit centered
    drawGlyph(
      canvas,
      numGlyph,
      space * 2.8,
      Offset(midX - digitWidth / 2, textY),
      color,
    );

    // If unbeamed, draw bracket lines on either side of the number
    if (!group.hasBeam) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = math.max(1.0, space * 0.1)
        ..style = PaintingStyle.stroke;

      final hookLen = space * 0.6;
      final hookSign = group.isAbove ? 1.0 : -1.0;
      final gapHalf = digitWidth * 0.9;

      // Left segment
      final leftStart = group.startX;
      final leftEnd = midX - gapHalf;
      if (leftEnd > leftStart) {
        canvas.drawLine(
          Offset(leftStart, group.y + hookSign * hookLen),
          Offset(leftStart, group.y),
          paint,
        );
        canvas.drawLine(
          Offset(leftStart, group.y),
          Offset(leftEnd, group.y),
          paint,
        );
      }

      // Right segment
      final rightStart = midX + gapHalf;
      final rightEnd = group.endX;
      if (rightEnd > rightStart) {
        canvas.drawLine(
          Offset(rightStart, group.y),
          Offset(rightEnd, group.y),
          paint,
        );
        canvas.drawLine(
          Offset(rightEnd, group.y),
          Offset(rightEnd, group.y + hookSign * hookLen),
          paint,
        );
      }
    }
  }
}
