import 'package:easy_piano/practice/practice_stage.dart';
import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:easy_piano/ui/staff/staff_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rh = StaffNote(72, 0, 1);
  const lh = StaffNote(48, 0, 1, leftHand: true);

  test('grand staff hides the staff with no notes', () {
    expect(fitStaves(Staves.grand, [rh]), Staves.treble);
    expect(fitStaves(Staves.grand, [lh]), Staves.bass);
    expect(fitStaves(Staves.grand, [rh, lh]), Staves.grand);
  });

  test('single staves and empty pages are left alone', () {
    expect(fitStaves(Staves.treble, [lh]), Staves.treble);
    expect(fitStaves(Staves.grand, const []), Staves.grand);
  });
}
