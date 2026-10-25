import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:easy_piano/ui/staff/staff_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArpeggioLayout geometry (values from MuseScore v450 and Leland)', () {
    const space = 10.0;

    test('staff line index: 0 is the top staff line, odd is a space', () {
      // Treble top line F5 (step of MIDI 77) is line 0, bottom line E4 is 8.
      final f5 = StaffPainter.diatonicStep(77);
      expect(ArpeggioLayout.staffLine(step: f5, topLineStep: f5), 0);
      expect(
        ArpeggioLayout.staffLine(
          step: StaffPainter.diatonicStep(64),
          topLineStep: f5,
        ),
        8,
      );
    });

    test('vertical bounds run from the head edges (headHeight / 2)', () {
      // 1.06 sp head (Leland uniE0A4 bounds) -> half 0.53 sp = 5.3 px.
      final v = ArpeggioLayout.verticalBounds(
        highestHeadY: 100,
        lowestHeadY: 140,
        topLine: 2,
        bottomLine: 6,
        space: space,
      );
      expect(v.top, closeTo(100 - 5.3, 1e-9));
      expect(v.bottom, closeTo(140 + 5.3, 1e-9));
    });

    test(
      'top rises 0.4 sp when both ends are on spaces, 0.25 sp otherwise',
      () {
        // calcTop: top note on a space (odd line) inside the staff.
        final spaceBoth = ArpeggioLayout.verticalBounds(
          highestHeadY: 100,
          lowestHeadY: 140,
          topLine: 1,
          bottomLine: 3,
          space: space,
        );
        expect(spaceBoth.top, closeTo(100 - 5.3 - 0.4 * space, 1e-9));

        final spaceLine = ArpeggioLayout.verticalBounds(
          highestHeadY: 100,
          lowestHeadY: 140,
          topLine: 1,
          bottomLine: 2,
          space: space,
        );
        expect(spaceLine.top, closeTo(100 - 5.3 - 0.25 * space, 1e-9));

        // Top note on a line: no rise.
        final onLine = ArpeggioLayout.verticalBounds(
          highestHeadY: 100,
          lowestHeadY: 140,
          topLine: 2,
          bottomLine: 3,
          space: space,
        );
        expect(onLine.top, closeTo(100 - 5.3, 1e-9));
      },
    );

    test('right edge: 0.4 sp left of the head, or 0.3 sp left of a sharp', () {
      expect(
        ArpeggioLayout.rightEdge(
          notes: [(headX: 100, hasAccidental: false)],
          space: space,
        ),
        closeTo(100 - 0.4 * space, 1e-9),
      );
      // Sharp at headX - 1.3 sp, then 0.3 sp more: 100 - 13 - 3 = 84.
      expect(
        ArpeggioLayout.rightEdge(
          notes: [(headX: 100, hasAccidental: true)],
          space: space,
        ),
        closeTo(100 - 13 - 0.3 * space, 1e-9),
      );
    });

    test('plain wiggle: fills + end, stacked upwards by the 0.88 sp advance', () {
      // h = 5 sp: fills = round((5 - 0.88) / 0.88) = 5, then the end glyph.
      final gs = ArpeggioLayout.layoutGlyphs(
        direction: ArpeggioDirection.plain,
        top: 0,
        bottom: 50,
        rightEdge: 100,
        space: space,
      );
      expect(gs, hasLength(6));
      expect(gs.every((g) => g.glyph == ArpeggioLayout.wiggleGlyph), isTrue);
      expect(gs.every((g) => g.angle == -math.pi / 2), isTrue);
      // First origin: 0.088 sp above the bottom. Next ones 8.8 px higher.
      expect(gs.first.origin.dy, closeTo(50 - 0.88, 1e-9));
      expect(gs[1].origin.dy - gs.first.origin.dy, closeTo(-8.8, 1e-9));
      // Right-aligned to the edge: the wiggle ink is 0 .. -0.656 sp left of it.
      expect(gs.first.origin.dx, closeTo(100, 1e-9));
    });

    test('up arrow ends with U+EAAD rotated -90 at the top', () {
      final gs = ArpeggioLayout.layoutGlyphs(
        direction: ArpeggioDirection.up,
        top: 0,
        bottom: 50,
        rightEdge: 100,
        space: space,
      );
      expect(gs.last.glyph, ArpeggioLayout.arrowGlyph);
      expect(gs.last.angle, -math.pi / 2);
      expect(gs.last.origin.dy, lessThan(gs.first.origin.dy));
      // The arrow reaches 0.332 sp right of the column origin.
      expect(gs.first.origin.dx, closeTo(100 - 3.32, 1e-9));
    });

    test('down arrow reuses U+EAAD rotated +90 and stacks downwards', () {
      final gs = ArpeggioLayout.layoutGlyphs(
        direction: ArpeggioDirection.down,
        top: 0,
        bottom: 50,
        rightEdge: 100,
        space: space,
      );
      expect(gs.last.glyph, ArpeggioLayout.arrowGlyph);
      expect(gs.last.angle, math.pi / 2);
      expect(gs.last.origin.dy, greaterThan(gs.first.origin.dy));
      // Down arrow reaches 1.04 sp to the right of its origin.
      expect(gs.first.origin.dx, closeTo(100 - 10.4, 1e-9));
    });

    test(
      'glissando starts at the start head edge and ends at the end head',
      () {
        final ends = ArpeggioLayout.glissandoEnds(
          startHead: const Offset(100, 50),
          endHead: const Offset(200, 40),
          space: 10,
        );
        expect(ends, isNotNull);
        // Head width 1.3 sp (Leland uniE0A4 advance 325 units).
        expect(ends!.from.dx, closeTo(100 + 1.3 * 10, 1e-9));
        expect(ends.to.dx, closeTo(200, 1e-9));
        expect(ends.from.dy, 50);
        expect(ends.to.dy, 40);
      },
    );

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
