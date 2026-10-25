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

/// Largest alpha difference between [a] and [b] in the box [x0..x1] x
/// [y0..y1] of a 600-px-wide image. Test fonts paint placeholder boxes, so
/// absolute "no ink" checks are unreliable; comparing with a render without
/// the ottava isolates what the ottava adds.
int _maxDiff(ByteData a, ByteData b, int x0, int y0, int x1, int y1) {
  var m = 0;
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final i = (y * 600 + x) * 4 + 3;
      final d = (a.getUint8(i) - b.getUint8(i)).abs();
      if (d > m) m = d;
    }
  }
  return m;
}

// Single staff, 600x400: space = 400 / 11 clamped to 20. Note x = 120 + beat
// * 60 (lineRatio 0.2, pixelsPerBeat 60).
StaffPainter _painter({
  required Staves staves,
  required List<StaffNote> notes,
  List<StaffOttava> ottavas = const [],
}) => StaffPainter(
  notes: notes,
  playheadBeat: ValueNotifier<double>(0),
  pixelsPerBeat: 60,
  lineRatio: 0.2,
  staves: staves,
  playheadColor: const Color(0xFFFF0000),
  inkColor: const Color(0xFF000000),
  ottavas: ottavas,
);

void main() {
  testWidgets('8va: dashed line 2 sp above the treble staff, hook down', (
    tester,
  ) async {
    // Treble bottom line at 200 + 2 sp = 240; top line at 160.
    // Line at 160 - 2 sp = 120; hook ends at 120 + 1 sp = 140.
    // C5 written, drawn as C4 under the 8va (notes at beats 0-1).
    const notes = [
      StaffNote(72, 0, 1),
      StaffNote(72, 1, 1),
      StaffNote(72, 2, 1),
      StaffNote(72, 3, 1),
    ];
    const va = StaffOttava(kind: OttavaKind.alta, startBeat: 0, endBeat: 2);
    final plain = await _render(
      tester,
      _painter(staves: Staves.treble, notes: notes),
    );
    final withVa = await _render(
      tester,
      _painter(staves: Staves.treble, notes: notes, ottavas: const [va]),
    );
    // The line between the first and the last note of the spanner (x 120..240).
    expect(_maxDiff(plain, withVa, 130, 118, 230, 122), greaterThan(100));
    // The hook at the right end (x 240) from y 120 down to 140.
    expect(_maxDiff(plain, withVa, 238, 126, 242, 134), greaterThan(100));
    // Nothing added above the line, nor past the end of the spanner.
    expect(_maxDiff(plain, withVa, 130, 100, 230, 112), 0);
    expect(_maxDiff(plain, withVa, 250, 118, 262, 122), 0);
  });

  testWidgets('8vb: dashed line 2 sp below the bass staff, hook up', (
    tester,
  ) async {
    // Bass staff only: top line at 200 - 2 sp = 160, bottom line at 240.
    // Line at 240 + 2 sp = 280; hook ends at 280 - 1 sp = 260.
    const notes = [
      StaffNote(36, 0, 1, leftHand: true),
      StaffNote(36, 1, 1, leftHand: true),
      StaffNote(36, 2, 1, leftHand: true),
    ];
    const vb = StaffOttava(
      kind: OttavaKind.bassa,
      startBeat: 0,
      endBeat: 2,
      leftHand: true,
    );
    final plain = await _render(
      tester,
      _painter(staves: Staves.bass, notes: notes),
    );
    final withVb = await _render(
      tester,
      _painter(staves: Staves.bass, notes: notes, ottavas: const [vb]),
    );
    expect(_maxDiff(plain, withVb, 130, 278, 230, 282), greaterThan(100));
    expect(_maxDiff(plain, withVb, 238, 266, 242, 274), greaterThan(100));
    // Nothing added below the line.
    expect(_maxDiff(plain, withVb, 130, 290, 230, 300), 0);
  });
}
