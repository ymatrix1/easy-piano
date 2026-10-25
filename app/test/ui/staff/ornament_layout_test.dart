import 'dart:io';
import 'dart:math' as math;
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
      // wiggleTrill: the fill of a trill's wavy line.
      expect(OrnamentLayout.wiggle.glyph, '\uEAA4');
    });

    test('mordent and turn are centred on the head at the given baseline', () {
      const space = 10.0;
      final centre = OrnamentLayout.headCentreX(100, space);
      expect(centre, closeTo(100 + 6.5, 1e-9));
      for (final kind in [OrnamentKind.mordent, OrnamentKind.turn]) {
        final g = OrnamentLayout.glyphFor(kind);
        final o = OrnamentLayout.ornamentOrigin(
          kind: kind,
          centreX: centre,
          baselineY: 50,
          space: space,
        );
        // Horizontal centre of the glyph box is the head centre.
        expect(
          o.dx + space * (g.swX + g.neX) / 2,
          closeTo(centre, 1e-9),
          reason: '$kind centred',
        );
        expect(o.dy, 50, reason: '$kind on the given baseline');
      }
    });

    test('chord top: stem tip for stem-up, top head for stem-down', () {
      // MuseScore chordlayout.cpp:1048-1077, gaps v450:193-194 (0.4 sp).
      const space = 10.0;
      // Stem up: tip 40 minus propertyDistanceStem (4 px).
      expect(
        OrnamentLayout.ornamentChordTopY(
          stemUp: true,
          stemTipY: 40,
          topHeadY: 60,
          space: space,
        ),
        closeTo(36, 1e-9),
      );
      // Stem down: head centre 60 minus half head 5.3 and propertyDistanceHead 4.
      expect(
        OrnamentLayout.ornamentChordTopY(
          stemUp: false,
          stemTipY: 40,
          topHeadY: 60,
          space: space,
        ),
        closeTo(60 - 5.3 - 4, 1e-9),
      );
    });

    test('mordent baseline: higher of the staff clearance and the chord', () {
      // chordlayout.cpp:1051 (staffTopY = -propertyDistance), :1111 (min).
      const space = 10.0;
      // Chord well below the staff: sits propertyDistance (4 px) above the top line.
      expect(
        OrnamentLayout.ornamentBaselineY(
          staffTopY: 100,
          chordTopY: 110.7,
          space: space,
        ),
        closeTo(96, 1e-9),
      );
      // Chord high above the staff: the chord clearance wins.
      expect(
        OrnamentLayout.ornamentBaselineY(
          staffTopY: 100,
          chordTopY: 50.7,
          space: space,
        ),
        closeTo(50.7, 1e-9),
      );
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

    test('notehead half height is the Leland bbox, 0.53 sp', () {
      // noteheadBlack bbox y -0.532..0.528 sp.
      expect(OrnamentLayout.headHalfHeightSp, 0.53);
    });

    test('trill baseline: default above the staff, lifted over the chord', () {
      // trillPosAbove y -0.5 (v450:266); trillMinDistance 0.5 (v450:1552).
      const space = 10.0;
      // Chord ink far below the default: the trill stays at staffTop - 5.
      expect(
        OrnamentLayout.trillBaselineY(
          staffTopY: 100,
          topInkY: 120,
          space: space,
        ),
        closeTo(95, 1e-9),
      );
      // Chord ink at 90: the trill clears it by 5 px, baseline 85.
      expect(
        OrnamentLayout.trillBaselineY(
          staffTopY: 100,
          topInkY: 90,
          space: space,
        ),
        closeTo(85, 1e-9),
      );
    });

    test('trill symbols: start glyph, then wiggleTrill fills (symbolLine)', () {
      // dom/trill.cpp:83-88. Start advance 1.732 sp, fill advance 0.88 sp.
      const space = 10.0;
      // w = 200, w1 = 17.32, w2 = 8.8: lrint(182.68 / 8.8) = lrint(20.76) = 21.
      final long = OrnamentLayout.trillSymbols(
        startX: 100,
        endX: 300,
        space: space,
      );
      expect(long.startX, 100);
      expect(long.fillXs, hasLength(21));
      expect(long.fillXs.first, closeTo(100 + 17.32, 1e-9));
      expect(long.fillXs.last, closeTo(100 + 17.32 + 20 * 8.8, 1e-9));

      // w = 10 < w1: no room for a fill, only the start glyph.
      final short = OrnamentLayout.trillSymbols(
        startX: 100,
        endX: 110,
        space: space,
      );
      expect(short.fillXs, isEmpty);

      // No next onset: endX equals startX, only the start glyph.
      final none = OrnamentLayout.trillSymbols(
        startX: 100,
        endX: 100,
        space: space,
      );
      expect(none.fillXs, isEmpty);
    });

    test('trill line ends one spatium before the next onset', () {
      // dom/trill.cpp:300: x = segment.x - spatium.
      expect(
        OrnamentLayout.trillEndX(nextOriginX: 300, space: 10),
        closeTo(290, 1e-9),
      );
    });

    test('grace head ends minNoteDistance left of the main chord ink', () {
      // minNoteDistance 0.5 sp (v450:156) > graceToMainNoteDist 0.45 (v450:377).
      const space = 10.0;
      final left = OrnamentLayout.graceHeadLeftX(
        leftmostInkX: 200,
        space: space,
      );
      // Grace head: 1.3 sp * 0.7 wide, plus the 0.5 sp gap.
      expect(left + 1.3 * 0.7 * space, closeTo(200 - 0.5 * space, 1e-9));
      expect(OrnamentLayout.graceNoteMag, 0.7);
    });

    test('grace stem is scaled and rises from the right of the head', () {
      const space = 10.0;
      // stemLength 3.5 sp (v450:151) * graceNoteMag 0.7.
      expect(
        OrnamentLayout.graceStemLength(space),
        closeTo(3.5 * 0.7 * 10, 1e-9),
      );
      // Stem right edge = head right edge: 100 + 1.3 * 0.7 * 10 = 109.1.
      expect(
        OrnamentLayout.graceStemRightX(graceLeftX: 100, space: space),
        closeTo(109.1, 1e-9),
      );
      // stemWidth 0.1 * 0.7 * 10 = 0.7, floored to 1 px (local choice).
      expect(OrnamentLayout.graceStemWidth(space), 1.0);
      expect(OrnamentLayout.graceStemWidth(20), closeTo(1.4, 1e-9));
      final x = OrnamentLayout.graceStemX(graceLeftX: 100, space: space);
      expect(x, closeTo(109.1 - 0.5, 1e-9));
    });

    test('stem slash is a line from the stem, angle 40 degrees', () {
      // tlayout.cpp:5378-5443 with v450:170-172 and angle 40.
      const space = 10.0;
      const stemRightX = 109.1;
      const stemTipY = 50.0;
      final slash = OrnamentLayout.stemSlash(
        stemRightX: stemRightX,
        stemTipY: stemTipY,
        space: space,
      );
      // leftHang = 1.3 * 0.7 * 10 / 2 = 4.55; startX = 109.1 - 4.55.
      expect(slash.from.dx, closeTo(104.55, 1e-9));
      // startY = tip + 0.7 * 2 sp * 10 * 0.66 = tip + 9.24 (below the tip).
      expect(slash.from.dy, closeTo(stemTipY + 9.24, 1e-9));
      // rightHang = 4.55 - 0.1 * 0.7 * 10 = 3.85; endX = 109.1 + 3.85.
      expect(slash.to.dx, closeTo(112.95, 1e-9));
      // endY = startY - (endX - startX) * tan(40 deg), rising to the right.
      expect(
        slash.to.dy,
        closeTo(59.24 - 8.4 * math.tan(40 * math.pi / 180), 1e-9),
      );
      expect(slash.to.dy, lessThan(slash.from.dy));
      // Thickness 0.125 * 0.7 * 10 = 0.875, floored to 1 px (local choice).
      expect(slash.width, 1.0);
    });

    test('an accidental moves the leftmost ink left, plain heads do not', () {
      // Accidental: gap 0.25 sp + sharp width 0.976 sp, at chord mag 1.
      expect(
        OrnamentLayout.leftmostInk(
          notes: [
            (headX: 50, accidental: null),
            (headX: 52, accidental: 'sharp'),
          ],
          space: 10,
        ),
        closeTo(52 - 10 * (0.25 + 0.976), 1e-9),
      );
      expect(
        OrnamentLayout.leftmostInk(
          notes: [(headX: 50, accidental: null)],
          space: 10,
        ),
        50,
      );
    });

    test('grace accidental sits left of the grace head at grace mag', () {
      // tdraw.cpp:2618: x -= symWidth + accidentalNoteDistance * mag.
      expect(
        OrnamentLayout.graceAccidentalX(
          graceLeftX: 100,
          accidental: 'sharp',
          space: 10,
        ),
        closeTo(100 - 10 * 0.7 * (0.976 + 0.25), 1e-9),
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

    testWidgets('a trill adds ink above its head, starting at the chord', (
      tester,
    ) async {
      // C5 on beat 4: head top at y 180, chord origin x 360. No later onset.
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
      // The trill glyph starts at the chord origin (trill segment pos, x1 = 0),
      // so its left ink is at about x 360 - 0.048 sp, not centred on the head.
      expect(_minX(extra), closeTo(_chordX, 3));
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
      // The fills lie between the trill glyph and the head at beat 6 (x 480).
      expect(extra.any((p) => p.$1 > 400 && p.$1 < 474), isTrue);
    });

    testWidgets('a trill with no later onset draws only the start glyph', (
      tester,
    ) async {
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
      // Only the start glyph (x 359..391) is new, no wave to the right.
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
      // slash ends about 8 px right of the stem, inside the gap.
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

double _minX(List<(int, int)> pixels) =>
    pixels.map((p) => p.$1).reduce((a, b) => a < b ? a : b).toDouble();

double _centreX(List<(int, int)> pixels) {
  final xs = pixels.map((p) => p.$1);
  return (xs.reduce((a, b) => a < b ? a : b) +
          xs.reduce((a, b) => a > b ? a : b)) /
      2;
}
