import 'dart:ui';

import 'package:flutter/material.dart';

import 'smufl.dart';

enum AccidentalType { natural, sharp, flat }

/// Manages key signatures and accidental spelling following MuseScore (`keysig.cpp`).
abstract final class KeySignatureLayout {
  // Sharps sequence: F, C, G, D, A, E, B
  static const sharpPitchClasses = [6, 1, 8, 3, 10, 5, 0];
  // Flats sequence: B, E, A, D, G, C, F
  static const flatPitchClasses = [10, 3, 8, 1, 6, 11, 4];

  // Natural note pitch classes affected when canceled
  static const sharpBaseNaturals = [
    5,
    0,
    7,
    2,
    9,
    4,
    11,
  ]; // F, C, G, D, A, E, B
  static const flatBaseNaturals = [11, 4, 9, 2, 7, 0, 5]; // B, E, A, D, G, C, F

  // Diatonic steps offsets from trebleBottomStep (E4)
  static const trebleSharpOffsets = [
    8,
    5,
    9,
    6,
    3,
    7,
    4,
  ]; // F5, C5, G5, D5, A4, E5, B4
  static const trebleFlatOffsets = [
    4,
    7,
    3,
    6,
    2,
    5,
    1,
  ]; // B4, E5, A4, D5, G4, C5, F4

  // Diatonic steps offsets from bassTopStep (A3)
  static const bassSharpOffsets = [
    -2,
    -5,
    -1,
    -4,
    -7,
    -3,
    -6,
  ]; // F3, C3, G3, D3, A2, E3, B2
  static const bassFlatOffsets = [
    -6,
    -3,
    -7,
    -4,
    -8,
    -5,
    -9,
  ]; // B2, E3, A2, D3, G2, C3, F2

  /// Calculates horizontal width needed for key signature of [fifths].
  static double width(int fifths, double space) {
    final count = fifths.abs();
    if (count == 0) return 0.0;
    return space * (0.6 + count * 1.05);
  }

  /// Returns the accidental (if any) needed for [pitch] given the [keyFifths].
  ///
  /// - If [explicit] is set, respects it.
  /// - If the note's pitch is already altered by the key signature, returns null (no inline accidental).
  /// - If the note cancels a key signature alteration (e.g. F natural in G major), returns [AccidentalType.natural].
  /// - Otherwise, if it's an accidental, returns [AccidentalType.sharp] or [AccidentalType.flat].
  static AccidentalType? accidentalFor({
    required int pitch,
    required int keyFifths,
    AccidentalType? explicit,
  }) {
    if (explicit != null) return explicit;

    final pc = pitch % 12;
    final count = keyFifths.abs();

    if (keyFifths > 0) {
      // Key with sharps
      final activeSharps = sharpPitchClasses.sublist(0, count);
      if (activeSharps.contains(pc)) {
        return null; // Already covered by key signature
      }
      final activeNaturals = sharpBaseNaturals.sublist(0, count);
      if (activeNaturals.contains(pc)) {
        // Naturalized note that is normally sharp in this key
        return AccidentalType.natural;
      }
      // Any other black key is sharped
      if (_isStandardBlackKey(pc)) {
        return AccidentalType.sharp;
      }
    } else if (keyFifths < 0) {
      // Key with flats
      final activeFlats = flatPitchClasses.sublist(0, count);
      if (activeFlats.contains(pc)) {
        return null; // Already covered by key signature
      }
      final activeNaturals = flatBaseNaturals.sublist(0, count);
      if (activeNaturals.contains(pc)) {
        return AccidentalType.natural;
      }
      if (_isStandardBlackKey(pc)) {
        return AccidentalType.flat;
      }
    } else {
      // C major / A minor
      if (_isStandardBlackKey(pc)) {
        return AccidentalType.sharp;
      }
    }
    return null;
  }

  static bool _isStandardBlackKey(int pc) {
    return pc == 1 || pc == 3 || pc == 6 || pc == 8 || pc == 10;
  }

  /// Renders key signature sharps or flats at [startX] for treble or bass staff.
  static void drawKeySignature({
    required Canvas canvas,
    required double startX,
    required int fifths,
    required bool onBass,
    required double space,
    required double trebleBottomY,
    required double bassTopY,
    required Color color,
    required void Function(Canvas, String, double, Offset, Color) drawGlyph,
  }) {
    final count = fifths.abs();
    if (count == 0) return;

    final isSharp = fifths > 0;
    final glyph = isSharp ? Smufl.accidentalSharp : Smufl.accidentalFlat;
    final glyphSize = space * 4;
    final half = space / 2;

    final offsets = isSharp
        ? (onBass ? bassSharpOffsets : trebleSharpOffsets)
        : (onBass ? bassFlatOffsets : trebleFlatOffsets);

    for (var i = 0; i < count && i < offsets.length; i++) {
      final x = startX + i * space * 1.05;
      final stepOffset = offsets[i];
      final y = onBass
          ? bassTopY - stepOffset * half
          : trebleBottomY - stepOffset * half;

      drawGlyph(canvas, glyph, glyphSize, Offset(x, y), color);
    }
  }
}
