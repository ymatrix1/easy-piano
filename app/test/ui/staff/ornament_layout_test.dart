import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:easy_piano/ui/staff/staff_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrnamentLayout geometry', () {
    test('glyphs are the SMuFL codepoints checked against the font', () {
      expect(OrnamentLayout.glyphFor(OrnamentKind.trill).glyph, '\uE566');
      expect(OrnamentLayout.glyphFor(OrnamentKind.mordent).glyph, '\uE56D');
      expect(OrnamentLayout.glyphFor(OrnamentKind.turn).glyph, '\uE567');
      // U+E560 is graceNoteAcciaccaturaStemUp, not the slash.
      expect(OrnamentLayout.slash.glyph, '\uE564');
    });

    test('ornament is centred on the head and its ink clears the top', () {
      const space = 10.0;
      final centre = OrnamentLayout.headCentreX(100, space);
      expect(centre, closeTo(100 + 6.5, 1e-9));
      for (final kind in OrnamentKind.values) {
        final g = OrnamentLayout.glyphFor(kind);
        final o = OrnamentLayout.ornamentOrigin(
          kind: kind,
          centreX: centre,
          topInkY: 50,
          space: space,
        );
        // Horizontal centre of the glyph box is the head centre.
        expect(
          o.dx + space * (g.swX + g.neX) / 2,
          closeTo(centre, 1e-9),
          reason: '$kind centred',
        );
        // Ink bottom (baseline - swY) sits the gap above the top ink.
        expect(
          o.dy - g.swY * space,
          closeTo(50 - OrnamentLayout.ornamentGapSp * space, 1e-9),
          reason: '$kind above the chord',
        );
      }
    });

    test('top ink is the highest head, or a stem tip above it', () {
      expect(
        OrnamentLayout.topInkY(headYs: [60, 70], stemTipYs: [], space: 10),
        60 - OrnamentLayout.headHalfHeightSp * 10,
      );
      // Stem up from the lowest head reaches above the top head.
      expect(
        OrnamentLayout.topInkY(headYs: [60, 70], stemTipYs: [35], space: 10),
        35,
      );
      // A stem tip below the top head changes nothing.
      expect(
        OrnamentLayout.topInkY(headYs: [60], stemTipYs: [65], space: 10),
        60 - OrnamentLayout.headHalfHeightSp * 10,
      );
    });

    test('trill line runs from the glyph to the next head, or is null', () {
      const space = 10.0;
      const origin = Offset(100, 50);
      final ends = OrnamentLayout.trillLineEnds(
        trillOrigin: origin,
        nextHeadLeftX: 300,
        space: space,
      );
      expect(ends, isNotNull);
      // Starts after the glyph's right edge, ends before the next head.
      expect(ends!.from.dx, greaterThan(100 + 1.532 * space));
      expect(ends.to.dx, closeTo(300 - 0.3 * space, 1e-9));
      expect(ends.from.dy, ends.to.dy);
      expect(ends.from.dy, closeTo(50 - (1.532 / 2) * space, 1e-9));

      // Too little room for a wave.
      expect(
        OrnamentLayout.trillLineEnds(
          trillOrigin: origin,
          nextHeadLeftX: 120,
          space: space,
        ),
        isNull,
      );
    });

    test('wave is continuous at both ends and stays within its amplitude', () {
      const space = 10.0;
      const from = Offset(0, 40);
      const to = Offset(53, 40);
      final pts = OrnamentLayout.wavePoints(from: from, to: to, space: space);
      expect(pts.first.dx, 0);
      expect(pts.last.dx, closeTo(53, 1e-9));
      expect(pts.first.dy, closeTo(40, 1e-9));
      expect(pts.last.dy, closeTo(40, 1e-9));
      // 53 / 7 = 7.6 periods, rounded to 8: 8 * 8 samples plus the end.
      expect(pts, hasLength(8 * 8 + 1));
      final amp = OrnamentLayout.waveAmplitudeSp * space;
      for (final p in pts) {
        expect((p.dy - 40).abs(), lessThanOrEqualTo(amp + 1e-9));
      }
      // The wave really swings: a sample reaches the peak.
      expect(
        pts.map((p) => p.dy).reduce((a, b) => a > b ? a : b),
        closeTo(40 + amp, 1e-6),
      );
    });

    test('grace head ends graceGapSp left of the main chord ink', () {
      const space = 10.0;
      final left = OrnamentLayout.graceHeadLeftX(
        leftmostInkX: 200,
        space: space,
      );
      // Scaled head: 1.3 sp * 0.6 wide, plus the gap.
      expect(left + 1.3 * 0.6 * space, closeTo(200 - 0.5 * space, 1e-9));
      expect(OrnamentLayout.graceScale, 0.6);
    });

    test('grace stem is scaled and rises from the right of the head', () {
      const space = 10.0;
      expect(
        OrnamentLayout.graceStemLength(space),
        closeTo(3.5 * 0.6 * 10, 1e-9),
      );
      final x = OrnamentLayout.graceStemX(graceLeftX: 100, space: space);
      expect(x, greaterThan(100 + 0.6 * 0.5 * space));
      expect(x, lessThan(100 + 1.3 * 0.6 * space));
    });

    test('slash is centred on the stem, scaled to the grace note', () {
      const space = 10.0;
      const stemX = 150.0;
      final o = OrnamentLayout.slashOrigin(
        stemX: stemX,
        stemFromY: 80,
        stemToY: 60,
        space: space,
      );
      final s = OrnamentLayout.graceScale * space;
      expect(o.dx + s * (0 + 1.956) / 2, closeTo(stemX, 1e-9));
      // Box centre sits at the stem middle (70): baseline is below it.
      expect(o.dy - s * (0 + 1.196) / 2, closeTo(70, 1e-9));
    });

    test('an accidental moves the leftmost ink left, plain heads do not', () {
      expect(
        OrnamentLayout.leftmostInk(
          notes: [
            (headX: 50, hasAccidental: false),
            (headX: 52, hasAccidental: true),
          ],
          space: 10,
        ),
        52 - 10,
      );
      expect(
        OrnamentLayout.leftmostInk(
          notes: [(headX: 50, hasAccidental: false)],
          space: 10,
        ),
        50,
      );
    });
  });

  group('ornament and acciaccatura painting', () {
    // flutter_test substitutes a placeholder font for unregistered families,
    // which would make glyph ink extents meaningless. Load the real Leland.
    setUpAll(() async {
      final bytes = await File('assets/fonts/Leland.otf').readAsBytes();
      final loader = FontLoader('Leland')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    });

    testWidgets('a trill adds ink above its head, centred on it', (
      tester,
    ) async {
      // C5 on beat 4: head top at y 180, centre x 373. No later onset, so no
      // wavy line muddies the centre of the ink.
      const notes = [StaffNote(72, 4, 2)];
      final base = await _render(tester, _painter(notes: notes));
      final marked = await _render(
        tester,
        _painter(
          notes: notes,
          ornaments: [const StaffOrnament(4, OrnamentKind.trill)],
        ),
      );
      final extra = _extraPixels(base, marked);
      expect(extra, isNotEmpty);
      expect(extra.every((p) => p.$2 < _headTopY), isTrue);
      expect(_centreX(extra), closeTo(_headCentreX, 15));
    });

    testWidgets('mordent and turn add ink above the head too', (tester) async {
      const notes = [StaffNote(72, 4, 2)];
      final base = await _render(tester, _painter(notes: notes));
      for (final kind in [OrnamentKind.mordent, OrnamentKind.turn]) {
        final marked = await _render(
          tester,
          _painter(notes: notes, ornaments: [StaffOrnament(4, kind)]),
        );
        final extra = _extraPixels(base, marked);
        expect(extra, isNotEmpty, reason: '$kind draws');
        expect(extra.every((p) => p.$2 < _headTopY), isTrue, reason: '$kind');
        expect(_centreX(extra), closeTo(_headCentreX, 15), reason: '$kind');
      }
    });

    testWidgets('a trill draws a wavy line to the next onset of its hand', (
      tester,
    ) async {
      const notes = [StaffNote(72, 4, 2), StaffNote(74, 6, 2)];
      final base = await _render(tester, _painter(notes: notes));
      final withNext = await _render(
        tester,
        _painter(
          notes: notes,
          ornaments: [const StaffOrnament(4, OrnamentKind.trill)],
        ),
      );
      final extra = _extraPixels(base, withNext);
      // The line lies between the trill glyph and the head at beat 6 (x 480).
      expect(extra.any((p) => p.$1 > 400 && p.$1 < 474), isTrue);
    });

    testWidgets('a trill with no later onset draws no line', (tester) async {
      const notes = [StaffNote(72, 4, 2)];
      final base = await _render(tester, _painter(notes: notes));
      final marked = await _render(
        tester,
        _painter(
          notes: notes,
          ornaments: [const StaffOrnament(4, OrnamentKind.trill)],
        ),
      );
      final extra = _extraPixels(base, marked);
      expect(extra, isNotEmpty);
      // Only the glyph (x 357..389) is new, no wave to the right.
      expect(extra.every((p) => p.$1 < 395), isTrue);
    });

    testWidgets('an ornament with no note at its beat draws nothing', (
      tester,
    ) async {
      const notes = [StaffNote(72, 4, 2)];
      final base = await _render(tester, _painter(notes: notes));
      final marked = await _render(
        tester,
        _painter(
          notes: notes,
          ornaments: [const StaffOrnament(2, OrnamentKind.trill)],
        ),
      );
      expect(_extraPixels(base, marked), isEmpty);
    });

    testWidgets('an acciaccatura adds a slashed grace note left of its chord', (
      tester,
    ) async {
      const notes = [StaffNote(72, 4, 2)];
      final base = await _render(tester, _painter(notes: notes));
      final marked = await _render(
        tester,
        _painter(
          notes: notes,
          acciaccaturas: [const StaffAcciaccatura(beat: 4, pitch: 67)],
        ),
      );
      final extra = _extraPixels(base, marked);
      expect(extra, isNotEmpty);
      // Grace head and stem sit left of the main chord (ink from x 360). The
      // slash box is centred on the stem and may touch the chord by a pixel.
      expect(extra.every((p) => p.$1 < _chordX + 2), isTrue);
      expect(extra.any((p) => p.$1 > 320), isTrue);
    });
  });
}

// Playhead at beat 0 with lineRatio 0.2 on a 600 px wide canvas: beat b sits
// at x = 120 + 60 b. Beat 4 is clear of the clef fade that masks the left part.
// Space is 20 px (400 / 11 clamped), so the treble staff's middle line is at y
// 200 and C5 (MIDI 72) sits at y 190, with its head top at 180.
const _chordX = 360.0;
const _headCentreX = 373.0;
const _headTopY = 180.0;
const _width = 600;
const _height = 400;

StaffPainter _painter({
  required List<StaffNote> notes,
  List<StaffOrnament> ornaments = const [],
  List<StaffAcciaccatura> acciaccaturas = const [],
}) => StaffPainter(
  notes: notes,
  playheadBeat: ValueNotifier<double>(0),
  pixelsPerBeat: 60,
  lineRatio: 0.2,
  staves: Staves.treble,
  playheadColor: const Color(0xFFFF0000),
  inkColor: const Color(0xFF000000),
  ornaments: ornaments,
  acciaccaturas: acciaccaturas,
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

double _centreX(List<(int, int)> pixels) {
  final xs = pixels.map((p) => p.$1);
  return (xs.reduce((a, b) => a < b ? a : b) +
          xs.reduce((a, b) => a > b ? a : b)) /
      2;
}
