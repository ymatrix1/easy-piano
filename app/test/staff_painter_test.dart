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

  test('grand staff leaves a gap between brace, system line and clefs', () {
    const space = 14.0;
    final g = StaffPainter.systemLayout(Staves.grand, space);
    // Brace (x0 = systemX - 1.25 sp, 0.9 sp wide, 0.35 sp stroke) stays
    // on screen and left of the system line.
    expect(g.systemX - space * 1.25 - space * 0.175, greaterThan(0));
    expect(g.systemX - space * 0.35 + space * 0.175, lessThan(g.systemX));
    expect(g.clefX - g.systemX, closeTo(space, 0.01));
    expect(g.clefRight, greaterThan(g.clefX + space * 2.7));

    final t = StaffPainter.systemLayout(Staves.treble, space);
    expect(t.systemX, 0);
    expect(t.clefX, space * 0.8);
  });

  test('note fade is clear of the clefs and opaque at the anchor', () {
    const space = 14.0, width = 390.0;
    final g = StaffPainter.systemLayout(Staves.grand, space);
    final f = StaffPainter.edgeFade(width, g.clefRight, 96, space).stops;
    expect(f[0] * width, closeTo(g.clefRight, 0.01)); // alpha 0 at clef edge
    expect(f[1] * width, lessThanOrEqualTo(96)); // opaque at anchor
    expect(f[2] * width, closeTo(width - space * 3, 0.01));
    expect(f[3], 1.0);
  });
}
