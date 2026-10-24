import 'dart:ui' as ui;

import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:easy_piano/ui/staff/staff_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dynamics and hairpins paint below the bottom staff', (
    tester,
  ) async {
    const size = Size(600, 400);
    final playhead = ValueNotifier<double>(0);
    // Treble only: space = 400 / 11 clamped to 20; bottom line at 200 + 2 sp.
    const space = 20.0;
    const bottomY = 200 + space * 2;
    final painter = StaffPainter(
      // Notes above the staff: no ledger lines below to confuse the sample.
      notes: const [
        StaffNote(72, 0, 1),
        StaffNote(72, 1, 1),
        StaffNote(72, 2, 1),
      ],
      playheadBeat: playhead,
      pixelsPerBeat: 60,
      lineRatio: 0.2,
      staves: Staves.treble,
      playheadColor: const Color(0xFFFF0000),
      inkColor: const Color(0xFF000000),
      dynamics: const [StaffDynamic(0, 'p')],
      hairpins: const [
        StaffHairpin(startBeat: 1, endBeat: 2.5, kind: HairpinKind.crescendo),
      ],
    );

    final rec = ui.PictureRecorder();
    painter.paint(Canvas(rec), size);
    final img = await tester.runAsync(
      () => rec.endRecording().toImage(size.width.toInt(), size.height.toInt()),
    );
    final bytes = (await tester.runAsync(
      () => img!.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;

    int maxAlpha(int x0, int y0, int x1, int y1) {
      var m = 0;
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          m = m > bytes.getUint8((y * 600 + x) * 4 + 3)
              ? m
              : bytes.getUint8((y * 600 + x) * 4 + 3);
        }
      }
      return m;
    }

    // Hairpin: tip at beat 1 (x = 120 + 60), arms open to beat 2.5 (x = 270).
    // Its centre sits 1.75 sp below the bottom line; the open end is at
    // centre -/+ 0.575 sp.
    final hairpinCentre = bottomY + 1.75 * space;
    expect(
      maxAlpha(
        262,
        (hairpinCentre - 12).toInt() - 3,
        272,
        (hairpinCentre - 12).toInt() + 3,
      ),
      greaterThan(0),
    );
    expect(
      maxAlpha(
        262,
        (hairpinCentre + 12).toInt() - 3,
        272,
        (hairpinCentre + 12).toInt() + 3,
      ),
      greaterThan(0),
    );

    // Dynamic `p` under the first note (x = 120), below the staff.
    expect(
      maxAlpha(
        118,
        (bottomY + 2 * space).toInt(),
        152,
        (bottomY + 4 * space).toInt(),
      ),
      greaterThan(0),
    );
  });
}
