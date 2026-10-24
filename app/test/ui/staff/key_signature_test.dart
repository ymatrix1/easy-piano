import 'package:easy_piano/ui/staff/key_signature.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KeySignatureLayout (MuseScore keysig.cpp style)', () {
    test('width is 0 for C major (0 fifths) and scales with fifths count', () {
      const space = 10.0;
      expect(KeySignatureLayout.width(0, space), 0.0);
      expect(KeySignatureLayout.width(1, space), greaterThan(space));
      expect(
        KeySignatureLayout.width(2, space),
        greaterThan(KeySignatureLayout.width(1, space)),
      );
      expect(
        KeySignatureLayout.width(-1, space),
        equals(KeySignatureLayout.width(1, space)),
      );
    });

    test('G major (1 sharp: F#): F# is covered by key signature, F natural needs natural', () {
      // F#4 is pitch 66 (pc 6)
      expect(KeySignatureLayout.accidentalFor(pitch: 66, keyFifths: 1), isNull);

      // F4 is pitch 65 (pc 5) -> canceled sharp, needs natural sign
      expect(
        KeySignatureLayout.accidentalFor(pitch: 65, keyFifths: 1),
        equals(AccidentalType.natural),
      );

      // G4 is pitch 67 (pc 7) -> untouched natural
      expect(KeySignatureLayout.accidentalFor(pitch: 67, keyFifths: 1), isNull);
    });

    test('F major (1 flat: Bb): Bb is covered by key signature, B natural needs natural', () {
      // Bb4 is pitch 70 (pc 10)
      expect(
        KeySignatureLayout.accidentalFor(pitch: 70, keyFifths: -1),
        isNull,
      );

      // B4 is pitch 71 (pc 11) -> canceled flat, needs natural sign
      expect(
        KeySignatureLayout.accidentalFor(pitch: 71, keyFifths: -1),
        equals(AccidentalType.natural),
      );

      // C5 is pitch 72 (pc 0) -> untouched natural
      expect(
        KeySignatureLayout.accidentalFor(pitch: 72, keyFifths: -1),
        isNull,
      );
    });

    test('C major (0 fifths): black keys get standard sharps', () {
      // F#4 (66) -> sharp
      expect(
        KeySignatureLayout.accidentalFor(pitch: 66, keyFifths: 0),
        equals(AccidentalType.sharp),
      );

      // C4 (60) -> natural, no accidental
      expect(KeySignatureLayout.accidentalFor(pitch: 60, keyFifths: 0), isNull);
    });
  });

  group('AccidentalState (MuseScore measure-level accidental memory)', () {
    test(
      'repeated accidental in same measure does not draw redundant glyph',
      () {
        final state = AccidentalState(keyFifths: 0); // C major
        // Step for C4 is 28
        const stepC4 = 28;

        // First C#4: requires sharp glyph
        final acc1 = state.processNote(step: stepC4, pitch: 61);
        expect(acc1, equals(AccidentalType.sharp));

        // Second C#4 in same measure: already sharp, no glyph
        final acc2 = state.processNote(step: stepC4, pitch: 61);
        expect(acc2, isNull);

        // Subsequent C4 natural in same measure: requires natural glyph
        final acc3 = state.processNote(step: stepC4, pitch: 60);
        expect(acc3, equals(AccidentalType.natural));

        // Repeated C4 natural in same measure: already natural, no glyph
        final acc4 = state.processNote(step: stepC4, pitch: 60);
        expect(acc4, isNull);

        // Next measure: reset() resets to key signature (C is natural)
        state.reset();
        final acc5 = state.processNote(step: stepC4, pitch: 60);
        expect(acc5, isNull);
      },
    );

    test('tied continuation note does not draw accidental glyph', () {
      final state = AccidentalState(keyFifths: 0);
      const stepC4 = 28;

      // First note: C#4 -> sharp
      expect(
        state.processNote(step: stepC4, pitch: 61),
        equals(AccidentalType.sharp),
      );

      // Tied note across barline: reset called, but isTiedContinuation is true
      state.reset();
      expect(
        state.processNote(step: stepC4, pitch: 61, isTiedContinuation: true),
        isNull,
      );
    });
  });
}
