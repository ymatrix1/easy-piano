import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:easy_piano/ui/staff/staff_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders [painter] at 600x400 and returns the RGBA bytes.
Future<ByteData> _render(WidgetTester tester, StaffPainter painter) async {
  const size = Size(600, 400);
  final rec = ui.PictureRecorder();
  painter.paint(Canvas(rec), size);
  final img = await tester.runAsync(() => rec.endRecording().toImage(600, 400));
  return (await tester.runAsync(
    () => img!.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
}

/// Max alpha in the box [x0..x1] x [y0..y1] of a 600-px-wide image.
int _maxAlpha(ByteData bytes, int x0, int y0, int x1, int y1) {
  var m = 0;
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final a = bytes.getUint8((y * 600 + x) * 4 + 3);
      if (a > m) m = a;
    }
  }
  return m;
}

// Treble only: space = 400 / 11 clamped to 20; bottom line at 200 + 2 sp.
const _space = 20.0;
const _bottomY = 200 + _space * 2;

StaffPainter _painter({
  List<StaffDynamic> dynamics = const [],
  List<StaffHairpin> hairpins = const [],
}) => StaffPainter(
  // Notes above the staff: no ledger lines below to confuse the sample.
  // C5 stems point down to y = 190 + 3.5 sp = 260.
  notes: const [StaffNote(72, 0, 1), StaffNote(72, 1, 1), StaffNote(72, 2, 1)],
  playheadBeat: ValueNotifier<double>(0),
  pixelsPerBeat: 60,
  lineRatio: 0.2,
  staves: Staves.treble,
  playheadColor: const Color(0xFFFF0000),
  inkColor: const Color(0xFF000000),
  dynamics: dynamics,
  hairpins: hairpins,
);

void main() {
  testWidgets('a hairpin clears the stems below the staff (autoplace)', (
    tester,
  ) async {
    final bytes = await _render(
      tester,
      _painter(
        hairpins: const [
          StaffHairpin(startBeat: 1, endBeat: 2.5, kind: HairpinKind.crescendo),
        ],
      ),
    );
    // Stem tips at 260; hairpinMinDistance 0.7 sp clears them: box top 274,
    // centre 274 + 1.27 sp / 2. Arms at centre -/+ 0.575 sp; the open end is
    // at x = 120 + 2.5 * 60 = 270.
    const boxTop = 260 + 0.7 * _space;
    const centre = boxTop + 1.27 * _space / 2;
    const half = 1.15 * _space / 2;
    expect(
      _maxAlpha(
        bytes,
        262,
        (centre - half).toInt() - 3,
        272,
        (centre - half).toInt() + 3,
      ),
      greaterThan(0),
    );
    expect(
      _maxAlpha(
        bytes,
        262,
        (centre + half).toInt() - 3,
        272,
        (centre + half).toInt() + 3,
      ),
      greaterThan(0),
    );
    // Nothing of the hairpin above its clearance line.
    expect(_maxAlpha(bytes, 175, 262, 275, 270), 0);
  });

  testWidgets('a dynamic sits 2 spaces below the staff and is centred', (
    tester,
  ) async {
    final bytes = await _render(
      tester,
      _painter(dynamics: const [StaffDynamic(0, 'p')]),
    );
    // Notehead centre of the first note: 120 + 0.59 sp. The glyph is drawn
    // in a box that starts 2 sp below the bottom line. Its ink must lie in
    // that band, around the centre.
    final cx = 120 + 0.59 * _space;
    expect(
      _maxAlpha(
        bytes,
        cx.toInt() - 15,
        (_bottomY + 2 * _space).toInt(),
        cx.toInt() + 15,
        (_bottomY + 4 * _space).toInt(),
      ),
      greaterThan(0),
    );
  });

  testWidgets('grand staff: RH dynamic centred between the staves, LH below', (
    tester,
  ) async {
    // Grand staff, 600x400: space = 14 (clamped), treble bottom line at
    // 168, bass top line at 210, bass bottom line at 266.
    const space = 14.0;
    const trebleBottom = 400 * 0.42;
    const bassTop = trebleBottom + 3 * space;
    const bassBottom = bassTop + 4 * space;
    final painter = StaffPainter(
      // C6 in the treble: stem down ends on the treble bottom line (168).
      notes: const [StaffNote(84, 0, 1)],
      playheadBeat: ValueNotifier<double>(0),
      pixelsPerBeat: 60,
      lineRatio: 0.2,
      staves: Staves.grand,
      playheadColor: const Color(0xFFFF0000),
      inkColor: const Color(0xFF000000),
      dynamics: const [
        StaffDynamic(0, 'p'),
        StaffDynamic(1, 'f', leftHand: true),
      ],
    );
    final bytes = await _render(tester, painter);

    // RH dynamic: its box sits in the gap, between the two staves.
    final rhCentre = 120 + 0.59 * space;
    expect(
      _maxAlpha(
        bytes,
        rhCentre.toInt() - 12,
        (trebleBottom + 2).toInt(),
        rhCentre.toInt() + 12,
        (bassTop - 2).toInt(),
      ),
      greaterThan(0),
    );

    // LH dynamic: below the bass staff, 2 spaces under its bottom line.
    final lhCentre = 120 + 60 + 0.59 * space;
    expect(
      _maxAlpha(
        bytes,
        lhCentre.toInt() - 12,
        (bassBottom + 2 * space).toInt(),
        lhCentre.toInt() + 12,
        (bassBottom + 4 * space).toInt(),
      ),
      greaterThan(0),
    );
  });
}
