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

  testWidgets(
    'stem directions, unison noteheads, voice-2 rest offset and hidden spacers',
    (tester) async {
      const size = Size(600, 400);
      final now = ValueNotifier<double>(0);
      final painter = StaffPainter(
        notes: const [
          // Spacer at beat 0: draws nothing
          StaffNote(60, 0, 1, isSpacer: true),
          // Note with stem down at beat 1
          StaffNote(64, 1, 1, stemDown: true),
          // Note with stem up at beat 2
          StaffNote(64, 2, 1, stemDown: false),
          // Unison note at beat 3 (twoStems)
          StaffNote(64, 3, 1, twoStems: true),
          // Rest voice 1 at beat 4
          StaffNote(60, 4, 1, isRest: true, voice: 1),
          // Rest voice 2 at beat 4 (offset down)
          StaffNote(60, 4, 1, isRest: true, voice: 2),
        ],
        playheadBeat: now,
        pixelsPerBeat: 60,
        lineRatio: 0.1,
        staves: Staves.treble,
        playheadColor: const Color(0xFFFF0000),
        inkColor: const Color(0xFF000000),
      );
      final rec = ui.PictureRecorder();
      painter.paint(Canvas(rec), size);
      final img = await tester.runAsync(
        () =>
            rec.endRecording().toImage(size.width.toInt(), size.height.toInt()),
      );
      final bytes = (await tester.runAsync(
        () => img!.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      expect(bytes.lengthInBytes, size.width.toInt() * size.height.toInt() * 4);
    },
  );

  group('barLineX', () {
    const space = 14.0;
    const anchorX = 200.0;
    const nowBeat = 0.0;
    const ppb = 70.0;

    test('without preceding notes: nominal offset space * 0.8', () {
      final bx = StaffPainter.barLineX(
        barBeat: 4.0,
        nowBeat: nowBeat,
        anchorX: anchorX,
        pixelsPerBeat: ppb,
        space: space,
        notes: const [],
      );
      final barX = anchorX + 4.0 * ppb;
      expect(bx, closeTo(barX - space * 0.8, 0.001));
    });

    test('with quarter note before bar: nominal offset retained', () {
      final notes = [const StaffNote(60, 3.0, 1.0)];
      final bx = StaffPainter.barLineX(
        barBeat: 4.0,
        nowBeat: nowBeat,
        anchorX: anchorX,
        pixelsPerBeat: ppb,
        space: space,
        notes: notes,
      );
      final barX = anchorX + 4.0 * ppb;
      expect(bx, closeTo(barX - space * 0.8, 0.001));
    });

    test('with eighth note before bar: balanced between stem and next bar', () {
      // Eighth note at beat 3.5, bar line at 4.0, next note at 4.0
      final notes = [
        const StaffNote(62, 3.5, 0.5), // D4 eighth note
        const StaffNote(64, 4.0, 1.0), // E4 quarter note
      ];
      final bx = StaffPainter.barLineX(
        barBeat: 4.0,
        nowBeat: nowBeat,
        anchorX: anchorX,
        pixelsPerBeat: ppb,
        space: space,
        notes: notes,
      );
      final barX = anchorX + 4.0 * ppb;
      final prevRight = anchorX + 3.5 * ppb + space * 1.18;
      final nominalBx = barX - space * 0.8;

      // Centered between prevRight and barX
      expect(bx, closeTo((prevRight + barX) / 2, 0.001));
      // Gives strictly more space to the eighth note stem than nominalBx
      expect(bx - prevRight, greaterThan(nominalBx - prevRight));
      expect(bx - prevRight, closeTo(barX - bx, 0.001));
    });

    test('with accidental on next note: stays clear of the sharp sign', () {
      const density = 95.0; // density for subdivisions
      final notes = [
        const StaffNote(62, 3.5, 0.5),
        const StaffNote(66, 4.0, 1.0), // F#4 (accidental at barX - 1.4 sp)
      ];
      final bx = StaffPainter.barLineX(
        barBeat: 4.0,
        nowBeat: nowBeat,
        anchorX: anchorX,
        pixelsPerBeat: density,
        space: space,
        notes: notes,
      );
      final barX = anchorX + 4.0 * density;
      final accidentalLeft = barX - space * 1.4;
      final prevRight = anchorX + 3.5 * density + space * 1.18;
      // Bar line must be between the preceding note stem and the accidental
      expect(bx, lessThan(accidentalLeft));
      expect(bx, greaterThan(prevRight));
    });
  });

  group('StaffPainter noteX accidental spacing', () {
    const space = 8.0;
    const anchorX = 100.0;
    const nowBeat = 0.0;
    const ppb = 50.0; // tight spacing

    test('accidental shifts note right if tight to preceding note', () {
      final notes = [
        const StaffNote(60, 0.0, 0.25), // C4 ending around beat 0.25
        const StaffNote(
          66,
          0.25,
          0.25,
        ), // F#4 on beat 0.25 (nominal 112.5 < minX 123.84)
      ];
      final x = StaffPainter.noteX(
        index: 1,
        notes: notes,
        anchorX: anchorX,
        nowBeat: nowBeat,
        pixelsPerBeat: ppb,
        space: space,
      );
      final nominalX = anchorX + 0.25 * ppb;
      // Because nominalX puts F# too close to C4 for the sharp sign (at x - space * 1.4),
      // noteX pushes it right
      expect(x, greaterThan(nominalX));
    });
  });
}
