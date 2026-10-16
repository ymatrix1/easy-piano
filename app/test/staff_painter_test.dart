import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:easy_piano/ui/staff/staff_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'diatonic steps: one step per letter, sharps share the natural step',
    () {
      final c4 = StaffPainter.diatonicStep(60);
      expect(StaffPainter.diatonicStep(62), c4 + 1); // D4
      expect(StaffPainter.diatonicStep(64), c4 + 2); // E4
      expect(StaffPainter.diatonicStep(61), c4); // C#4 drawn on C line
      expect(StaffPainter.diatonicStep(72), c4 + 7); // C5
      expect(StaffPainter.diatonicStep(48), c4 - 7); // C3
    },
  );

  test('demo score is sorted by beat for binary-search culling', () {
    final notes = odeToJoyDemo(times: 3);
    for (var i = 1; i < notes.length; i++) {
      expect(notes[i].beat >= notes[i - 1].beat, isTrue);
    }
    expect(notes.where((n) => n.leftHand).length, 12);
  });
}
