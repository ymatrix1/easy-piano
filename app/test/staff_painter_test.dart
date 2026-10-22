import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:easy_piano/ui/staff/staff_painter.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
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
    // Brace (x0 = systemX - 1.9 sp, 1.4 sp wide, 0.45 sp stroke) stays
    // on screen and left of the system line.
    expect(g.systemX - space * 1.9 - space * 0.225, greaterThan(0));
    expect(g.systemX - space * 0.5 + space * 0.225, lessThan(g.systemX));
    expect(g.clefX - g.systemX, closeTo(space, 0.01));
    expect(g.clefRight, greaterThan(g.clefX + space * 2.7));

    final t = StaffPainter.systemLayout(Staves.treble, space);
    expect(t.systemX, space * 0.6);
    expect(t.clefX - t.systemX, closeTo(space, 0.01));
  });

  test('edge fade is clear at the clefs and opaque before the anchor', () {
    const space = 14.0;
    final g = StaffPainter.systemLayout(Staves.grand, space);
    final f = StaffPainter.edgeFade(g.clefRight, 104, space);
    expect(f.clear, g.clefRight); // nothing drawn left of the clef edge
    expect(f.full, greaterThan(f.clear));
    expect(f.full, lessThanOrEqualTo(104)); // current note never dimmed
    // Anchor right next to the clefs: still a valid (non-empty) ramp.
    final tight = StaffPainter.edgeFade(g.clefRight, g.clefRight + 5, space);
    expect(tight.full, greaterThan(tight.clear));
  });

  testWidgets('finger labels fade with their notes and cull behind the clef', (
    tester,
  ) async {
    const size = Size(400, 400);
    final now = ValueNotifier<double>(3);
    final painter = StaffPainter(
      notes: const [
        StaffNote(64, 0, 1, finger: 5), // x = 80: behind the clef edge
        StaffNote(64, 1.5, 1, finger: 4), // inside the fade ramp
        StaffNote(64, 3, 1, finger: 3), // current note, at the anchor
      ],
      playheadBeat: now,
      pixelsPerBeat: 40,
      lineRatio: 0.5,
      staves: Staves.treble,
      playheadColor: const Color(0xFFFF0000),
      inkColor: const Color(0xFF000000),
    );
    final rec = ui.PictureRecorder();
    painter.paint(Canvas(rec), size);
    final img = await tester.runAsync(
      () => rec.endRecording().toImage(size.width.toInt(), size.height.toInt()),
    );
    final bytes = (await tester.runAsync(
      () => img!.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    // Max alpha in a box around a label.
    int alphaAround(double cx, double cy) {
      var m = 0;
      for (var y = cy.toInt() - 5; y <= cy.toInt() + 5; y++) {
        for (var x = cx.toInt() - 5; x <= cx.toInt() + 5; x++) {
          m = math.max(m, bytes.getUint8((y * 400 + x) * 4 + 3));
        }
      }
      return m;
    }

    const space = 20.0; // height 400 / 11 clamps to 20
    final cy = 200 + space * 2 - space * 4 - space * 3.6; // staffTop - 3.6 sp
    expect(alphaAround(80 + space * 0.6, cy), 0);
    final mid = alphaAround(80 + 60 + space * 0.6, cy);
    expect(mid, inInclusiveRange(1, 254));
    expect(alphaAround(200 + space * 0.6, cy), 255);
  });
}
