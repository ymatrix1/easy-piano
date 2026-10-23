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
}
