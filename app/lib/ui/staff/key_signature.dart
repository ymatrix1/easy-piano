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

/// Tracks accidental alterations within a measure per MuseScore `AccidentalState` (`key.cpp` / `measure.cpp`).
///
/// Within a measure, accidentals apply to all subsequent notes of that pitch/step
/// until the barline. Tied continuation notes across barlines or beats do not
/// repeat accidentals. When crossing a barline, the accidental state resets to the key signature.
class AccidentalState {
  AccidentalState({required this.keyFifths});

  final int keyFifths;
  final Map<int, AccidentalType> _state = {};

  /// Resets accidental memory back to the key signature for the start of a new measure.
  void reset() {
    _state.clear();
  }

  /// Default alteration for a diatonic step according to the key signature.
  AccidentalType defaultForKey(int step) {
    final stepMod7 = ((step % 7) + 7) % 7;
    // Diatonic step mapping: 0=C, 1=D, 2=E, 3=F, 4=G, 5=A, 6=B.
    final count = keyFifths.abs();
    if (keyFifths > 0) {
      // Sharps sequence steps: F(3), C(0), G(4), D(1), A(5), E(2), B(6)
      const sharpSteps = [3, 0, 4, 1, 5, 2, 6];
      for (var i = 0; i < count && i < sharpSteps.length; i++) {
        if (sharpSteps[i] == stepMod7) return AccidentalType.sharp;
      }
    } else if (keyFifths < 0) {
      // Flats sequence steps: B(6), E(2), A(5), D(1), G(4), C(0), F(3)
      const flatSteps = [6, 2, 5, 1, 4, 0, 3];
      for (var i = 0; i < count && i < flatSteps.length; i++) {
        if (flatSteps[i] == stepMod7) return AccidentalType.flat;
      }
    }
    return AccidentalType.natural;
  }

  /// Calculates the accidental symbol to display (if any) for a note at [step] with [pitch] and optional [explicit].
  ///
  /// Updates the internal state for [step].
  AccidentalType? processNote({
    required int step,
    required int pitch,
    AccidentalType? explicit,
    bool isTiedContinuation = false,
  }) {
    if (isTiedContinuation && explicit == null) {
      return null;
    }

    final defaultKeyAlt = defaultForKey(step);
    final accAgainstKey = KeySignatureLayout.accidentalFor(
      pitch: pitch,
      keyFifths: keyFifths,
      explicit: explicit,
    );
    final soundingAlt = accAgainstKey ?? defaultKeyAlt;
    final currentAlt = _state[step] ?? defaultKeyAlt;

    if (explicit != null) {
      _state[step] = explicit;
      return explicit;
    }

    if (soundingAlt != currentAlt) {
      _state[step] = soundingAlt;
      return soundingAlt;
    }

    return null;
  }
}
