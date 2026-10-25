import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:easy_piano/ui/staff/staff_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArpeggioLayout geometry', () {
    test('wiggle glyphs stack from top to bottom, at least one', () {
      final flat = ArpeggioLayout.wiggleBaselines(
        top: 100,
        bottom: 100,
        space: 10,
      );
      expect(flat, hasLength(1));

      // 60 / (0.656 * 10) = 9.1 glyphs, so ten reach past the bottom.
      final ys = ArpeggioLayout.wiggleBaselines(top: 0, bottom: 60, space: 10);
      expect(ys, hasLength(10));
      expect(ys.first, closeTo(6.56, 1e-9));
      expect(ys.last, closeTo(65.6, 1e-9));
    });

    test('glyph right edge sits clearanceSp left of the leftmost ink', () {
      final ox = ArpeggioLayout.originX(leftmostInkX: 100, space: 10);
      expect(
        ox + ArpeggioLayout.wiggleRightSp * 10,
        closeTo(100 - ArpeggioLayout.clearanceSp * 10, 1e-9),
      );
    });

    test('an accidental moves the leftmost ink left, plain heads do not', () {
      final plain = ArpeggioLayout.leftmostInk(
        notes: [
          (headX: 50, hasAccidental: false),
          (headX: 52, hasAccidental: false),
        ],
        space: 10,
      );
      expect(plain, 50);

      final withSharp = ArpeggioLayout.leftmostInk(
        notes: [
          (headX: 50, hasAccidental: false),
          (headX: 52, hasAccidental: true),
        ],
        space: 10,
      );
      expect(withSharp, 52 - ArpeggioLayout.accidentalWidthSp * 10);
    });

    test('arrows: up above the stack, down below it, plain has none', () {
      expect(
        ArpeggioLayout.arrowBaseline(
          direction: ArpeggioDirection.plain,
          top: 50,
          bottom: 80,
          space: 10,
        ),
        isNull,
      );
      expect(ArpeggioLayout.arrowGlyph(ArpeggioDirection.plain), isNull);

      // Up: arrow body (0.332 sp below its baseline) ends at the stack top.
      final up = ArpeggioLayout.arrowBaseline(
        direction: ArpeggioDirection.up,
        top: 50,
        bottom: 80,
        space: 10,
      );
      expect(up! + ArpeggioLayout.arrowBelowSp * 10, closeTo(50, 1e-9));
      expect(ArpeggioLayout.arrowGlyph(ArpeggioDirection.up), '\uEAAD');

      // Down: arrow top (1.04 sp above its baseline) starts at the stack bottom.
      final down = ArpeggioLayout.arrowBaseline(
        direction: ArpeggioDirection.down,
        top: 50,
        bottom: 80,
        space: 10,
      );
      expect(down! - ArpeggioLayout.arrowAboveSp * 10, closeTo(80, 1e-9));
      expect(ArpeggioLayout.arrowGlyph(ArpeggioDirection.down), '\uEAAE');
    });

    test('glissando joins the two heads with a gap at each end', () {
      final ends = ArpeggioLayout.glissandoEnds(
        startHead: const Offset(100, 50),
        endHead: const Offset(200, 40),
        space: 10,
      );
      expect(ends, isNotNull);
      expect(ends!.from.dx, closeTo(100 + 1.18 * 10 / 2, 1e-9));
      expect(ends.to.dx, closeTo(200 - 0.3 * 10, 1e-9));
      expect(ends.from.dy, 50);
      expect(ends.to.dy, 40);
    });

    test('glissando to a note on the left draws nothing', () {
      expect(
        ArpeggioLayout.glissandoEnds(
          startHead: const Offset(200, 50),
          endHead: const Offset(100, 40),
          space: 10,
        ),
        isNull,
      );
    });

    test('gliss label sits above the midpoint of the line', () {
      final c = ArpeggioLayout.glissandoLabelCentre(
        from: const Offset(0, 40),
        to: const Offset(100, 60),
        space: 10,
      );
      expect(c.dx, 50);
      expect(c.dy, closeTo(50 - 12, 1e-9));
    });

    test('closestPair picks the two nearest pitches', () {
      expect(ArpeggioLayout.closestPair([60, 64], [67, 70]), (1, 0));
      expect(ArpeggioLayout.closestPair([], [60]), isNull);
      expect(ArpeggioLayout.closestPair([60], []), isNull);
    });
  });

  group('arpeggio and glissando painting', () {
    // flutter_test substitutes a placeholder font for unregistered families,
    // which would make glyph ink extents meaningless. Load the real Leland.
    setUpAll(() async {
      final bytes = await File('assets/fonts/Leland.otf').readAsBytes();
      final loader = FontLoader('Leland')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    });

    testWidgets('an arpeggio only adds ink left of its chord', (tester) async {
      const chord = [
        StaffNote(72, 4, 2),
        StaffNote(76, 4, 2),
        StaffNote(79, 4, 2),
      ];
      final base = await _render(tester, _painter(notes: chord));
      final marked = await _render(
        tester,
        _painter(notes: chord, arpeggios: [const StaffArpeggio(4)]),
      );
      final extra = _extraPixels(base, marked);
      expect(extra, isNotEmpty);
      // Noteheads sit at x = 360; the wiggle stays left of them.
      expect(extra.every((p) => p.$1 < _chordX), isTrue);
    });

    testWidgets('a glissando draws ink between its two notes', (tester) async {
      const notes = [StaffNote(72, 4, 1), StaffNote(79, 6, 1)];
      final base = await _render(tester, _painter(notes: notes));
      final marked = await _render(
        tester,
        _painter(
          notes: notes,
          glissandi: [const StaffGlissando(startBeat: 4, endBeat: 6)],
        ),
      );
      final extra = _extraPixels(base, marked);
      expect(extra, isNotEmpty);
      // Heads at x = 360 (beat 4) and x = 480 (beat 6).
      // The line runs between the heads. The `gliss.` label is centred on it
      // and, under flutter_test's placeholder text font, is a wide box that
      // reaches about 30 px past each head.
      expect(extra.any((p) => p.$1 > _chordX && p.$1 < _gissX), isTrue);
      expect(
        extra.every((p) => p.$1 > _chordX - 40 && p.$1 < _gissX + 40),
        isTrue,
      );
    });
  });
}

// Playhead at beat 0 with lineRatio 0.2 on a 600 px wide canvas: beat b sits
// at x = 120 + 60 b. Beat 4 is clear of the clef fade that masks the left part.
const _chordX = 360.0;
const _gissX = 480.0;
const _width = 600;
const _height = 400;

StaffPainter _painter({
  required List<StaffNote> notes,
  List<StaffArpeggio> arpeggios = const [],
  List<StaffGlissando> glissandi = const [],
}) => StaffPainter(
  notes: notes,
  playheadBeat: ValueNotifier<double>(0),
  pixelsPerBeat: 60,
  lineRatio: 0.2,
  staves: Staves.treble,
  playheadColor: const Color(0xFFFF0000),
  inkColor: const Color(0xFF000000),
  arpeggios: arpeggios,
  glissandi: glissandi,
);

/// Renders [painter] and returns the raw RGBA bytes.
Future<ByteData> _render(WidgetTester tester, StaffPainter painter) async {
  final rec = ui.PictureRecorder();
  painter.paint(Canvas(rec), const Size(600, 400));
  final img = await tester.runAsync(
    () => rec.endRecording().toImage(_width, _height),
  );
  return (await tester.runAsync(
    () => img!.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
}

/// Pixels inked in [marked] but empty in [base], as (x, y).
List<(int, int)> _extraPixels(ByteData base, ByteData marked) {
  final out = <(int, int)>[];
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      final a = (y * _width + x) * 4 + 3;
      if (marked.getUint8(a) > 0 && base.getUint8(a) == 0) out.add((x, y));
    }
  }
  return out;
}
