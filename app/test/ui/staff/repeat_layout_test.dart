import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_piano/ui/staff/repeat_layout.dart';
import 'package:easy_piano/ui/staff/song_marks_parser.dart';
import 'package:easy_piano/ui/staff/staff_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RepeatLayout geometry', () {
    // space 10: thin 1.8, thick 5.5, gap 3.7, dot separation 3.7, dot 4.16.
    test('start repeat: thick, thin, then dots, from the group origin', () {
      final g = RepeatLayout.barlineGeometry(
        start: true,
        end: false,
        x: 100,
        space: 10,
      );
      // Raw layout from 0: thick centre 2.75, thin 10.1, dots 14.7, right 18.86.
      // The group is centred on x = 100, so it starts at 100 - 9.43.
      expect(g.thickX, hasLength(1));
      expect(g.thinX, hasLength(1));
      expect(g.dotsX, hasLength(1));
      expect(g.thickX.single, closeTo(100 - 9.43 + 2.75, 1e-9));
      expect(g.thinX.single, closeTo(100 - 9.43 + 10.1, 1e-9));
      expect(g.dotsX.single, closeTo(100 - 9.43 + 14.7, 1e-9));
      expect(g.thickWidth, closeTo(5.5, 1e-9));
      expect(g.thinWidth, closeTo(1.8, 1e-9));
      expect(g.left, closeTo(100 - 9.43, 1e-9));
      expect(g.right, closeTo(100 + 9.43, 1e-9));
      expect(g.leftDots, isFalse);
    });

    test('end repeat: dots, thin, then thick line; same width as start', () {
      final g = RepeatLayout.barlineGeometry(
        start: false,
        end: true,
        x: 100,
        space: 10,
      );
      // Raw: dots 0, thin 8.76, thick 16.11, right 18.86.
      expect(g.dotsX.single, closeTo(100 - 9.43, 1e-9));
      expect(g.thinX.single, closeTo(100 - 9.43 + 8.76, 1e-9));
      expect(g.thickX.single, closeTo(100 - 9.43 + 16.11, 1e-9));
      expect(g.right - g.left, closeTo(18.86, 1e-9));
      expect(g.leftDots, isTrue);
    });

    test(
      'start and end (:|:) mirror the dots around the middle thick line',
      () {
        final g = RepeatLayout.barlineGeometry(
          start: true,
          end: true,
          x: 100,
          space: 10,
        );
        // Raw: dots 0, thin 8.76, thick 16.11, thin 23.46, dots 28.06, right
        // 32.22. Centred on 100.
        expect(g.thinX, hasLength(2));
        expect(g.thickX, hasLength(1));
        expect(g.dotsX, hasLength(2));
        expect(g.right - g.left, closeTo(32.22, 1e-9));
        // The middle thick line sits at the centre of the group.
        expect(g.thickX.single, closeTo((g.left + g.right) / 2, 1e-9));
      },
    );

    test('no repeat flags: empty group', () {
      final g = RepeatLayout.barlineGeometry(
        start: false,
        end: false,
        x: 50,
        space: 10,
      );
      expect(g.thinX, isEmpty);
      expect(g.thickX, isEmpty);
      expect(g.dotsX, isEmpty);
    });

    test('two dots sit in spaces 3 (upper) and 2 (lower) of a staff', () {
      // Bottom line at y 200, space 10: space 2 is 1.5 sp above, space 3 is
      // 2.5 sp above.
      final ys = RepeatLayout.dotCentresY(bottomLineY: 200, space: 10);
      expect(ys, [175, 185]);
    });

    test('volta line sits 3 sp above the top line; hooks run 2.2 sp down', () {
      final v = RepeatLayout.voltaGeometry(
        startX: 40,
        endX: 90,
        staffTopY: 100,
        space: 10,
        closedEnd: true,
      );
      expect(v.lineY, closeTo(70, 1e-9));
      expect(v.hookBottomY, closeTo(92, 1e-9));
      expect(v.startX, 40);
      expect(v.endX, 90);
      expect(v.closedEnd, isTrue);
      // Label: start + voltaOffset x 0.6 sp = 40 + 6; line + voltaOffset y
      // 2.2 sp (below the line, volta.cpp:109) = 70 + 22.
      expect(v.labelOrigin.dx, closeTo(46, 1e-9));
      expect(v.labelOrigin.dy, closeTo(92, 1e-9));
    });

    test(
      'volta starts after a start repeat and stops before an end repeat',
      () {
        final start = RepeatLayout.barlineGeometry(
          start: true,
          end: false,
          x: 100,
          space: 10,
        );
        final end = RepeatLayout.barlineGeometry(
          start: false,
          end: true,
          x: 200,
          space: 10,
        );
        // volta.cpp:376: start = segment width (group right) - lw / 2 with
        // lw = 1.1 sp at space 10, so minus 0.55.
        expect(
          RepeatLayout.voltaStartX(barX: 100, group: start, space: 10),
          closeTo(start.right - 0.55, 1e-9),
        );
        // volta.cpp:387-390: origin + dot width 4.16 + separation 3.7 +
        // lw / 2 0.55 = origin + 8.41.
        expect(
          RepeatLayout.voltaEndX(barX: 200, group: end, space: 10),
          closeTo(end.left + 8.41, 1e-9),
        );
      },
    );

    test('a volta without a repeat sign uses the bar line centre', () {
      // Plain bar: centre = origin + barWidth / 2 (tdraw.cpp:735). Start =
      // origin + barWidth - lw / 2 = centre + (1.8 - 1.1) / 2 = centre + 0.35.
      expect(
        RepeatLayout.voltaStartX(barX: 100, group: null, space: 10),
        closeTo(100.35, 1e-9),
      );
      // End = origin + lw / 2 = centre - 0.35 (volta.cpp:390).
      expect(
        RepeatLayout.voltaEndX(barX: 200, group: null, space: 10),
        closeTo(199.65, 1e-9),
      );
    });

    test('segno and coda are centred on x, 18 pt at space 20', () {
      // 18 pt / 4.96 pt per sp = 3.629 sp em = 72.58 px at space 20.
      expect(RepeatLayout.navigationGlyphEm(20), closeTo(72.58, 0.01));
      // Segno is 0.654 em wide: origin 360 - 0.327 * 72.58 = 336.27.
      expect(
        RepeatLayout.navigationGlyphOriginX(
          kind: NavigationKind.segno,
          x: 360,
          space: 20,
        ),
        closeTo(336.27, 0.01),
      );
    });

    test('volta and jump text sizes: 11 pt at space 20', () {
      // 11 pt / 4.96 pt per sp = 2.218 sp, 44.35 px at space 20.
      expect(RepeatLayout.voltaFontSize(20), closeTo(44.35, 0.01));
      expect(RepeatLayout.jumpFontSize(20), closeTo(44.35, 0.01));
    });

    test('a volta covers its start beat and not its end beat', () {
      const voltas = [
        StaffVolta(startBeat: 4, endBeat: 8, number: 1, closedEnd: true),
      ];
      expect(RepeatLayout.withinVolta(4, voltas), isTrue);
      expect(RepeatLayout.withinVolta(7.5, voltas), isTrue);
      expect(RepeatLayout.withinVolta(8, voltas), isFalse);
      expect(RepeatLayout.withinVolta(3.9, voltas), isFalse);
    });

    test('navigation sits 2 sp above the staff (markerPosAbove)', () {
      expect(
        RepeatLayout.navigationBaselineY(
          staffTopY: 100,
          space: 10,
          overVolta: false,
        ),
        80,
      );
    });

    test(
      'navigation over a volta: volta line 3 sp + repeatMinDistance 0.5 sp',
      () {
        // Volta line at 100 - 30 = 70; the mark's baseline 0.5 sp above it.
        expect(
          RepeatLayout.navigationBaselineY(
            staffTopY: 100,
            space: 10,
            overVolta: true,
          ),
          closeTo(65, 1e-9),
        );
      },
    );

    test('codepoints: repeat dot, segno, coda; text for the jumps', () {
      expect(RepeatLayout.repeatDotGlyph, '\uE044');
      expect(RepeatLayout.navigationGlyph(NavigationKind.segno), '\uE047');
      expect(RepeatLayout.navigationGlyph(NavigationKind.coda), '\uE048');
      expect(RepeatLayout.navigationGlyph(NavigationKind.dcAlFine), isNull);
      expect(
        RepeatLayout.navigationLabel(NavigationKind.dcAlFine),
        'D.C. al Fine',
      );
      expect(
        RepeatLayout.navigationLabel(NavigationKind.dsAlCoda),
        'D.S. al Coda',
      );
      expect(
        RepeatLayout.navigationLabel(NavigationKind.dcAlCoda),
        'D.C. al Coda',
      );
      expect(
        RepeatLayout.navigationLabel(NavigationKind.dsAlFine),
        'D.S. al Fine',
      );
      expect(RepeatLayout.navigationLabel(NavigationKind.fine), 'Fine');
      expect(RepeatLayout.navigationLabel(NavigationKind.toCoda), 'To Coda');
      expect(RepeatLayout.navigationLabel(NavigationKind.segno), isNull);
    });
  });

  group('repeat, volta and navigation painting', () {
    // flutter_test substitutes a placeholder font for unregistered families,
    // which would make glyph ink extents meaningless. Load the real Leland.
    setUpAll(() async {
      final bytes = await File('assets/fonts/Leland.otf').readAsBytes();
      final loader = FontLoader('Leland')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    });

    // Single treble staff on a 600 x 400 canvas: space 20, top line y 160,
    // bottom line y 240. Playhead at beat 0, lineRatio 0.2: beat b sits at
    // x = 120 + 60 b. With no notes the bar line sits 0.8 sp left of it.
    testWidgets('a repeat end adds ink on the bar line and both dot rows', (
      tester,
    ) async {
      final base = await _render(tester, _painter());
      final marked = await _render(
        tester,
        _painter(repeatBarlines: [const StaffRepeatBarline(4, end: true)]),
      );
      final extra = _extraPixels(base, marked);
      expect(extra, isNotEmpty);
      // Group centred on x = 344: dots from about 325, thick line near 357.
      expect(extra.every((p) => p.$1 > 320 && p.$1 < 370), isTrue);
      // Dot rows: centres at y 190 and 210.
      expect(extra.any((p) => p.$2 >= 185 && p.$2 <= 195), isTrue);
      expect(extra.any((p) => p.$2 >= 205 && p.$2 <= 215), isTrue);
      // Thin line between the staff lines (y 170 has no staff line).
      expect(
        extra.any((p) => p.$2 == 170 && p.$1 >= 340 && p.$1 <= 345),
        isTrue,
      );
    });

    testWidgets('a volta adds a line above the staff with two hooks', (
      tester,
    ) async {
      final base = await _render(tester, _painter());
      final marked = await _render(
        tester,
        _painter(
          voltas: [
            const StaffVolta(
              startBeat: 4,
              endBeat: 6,
              number: 1,
              closedEnd: true,
            ),
          ],
        ),
      );
      final extra = _extraPixels(base, marked);
      expect(extra, isNotEmpty);
      // Everything sits above the top staff line (y 160).
      expect(extra.every((p) => p.$2 < 160), isTrue);
      // The horizontal line at y 100 runs from x 344 to 464.
      expect(extra.any((p) => p.$2 == 100 && p.$1 > 360 && p.$1 < 450), isTrue);
      // Plain bar at 344 (centre): start 344.7 (+0.7 for lw 2.2 px), closed
      // end 463.3 (-0.7). Hooks run 2.2 sp = 44 px down from y 100.
      expect(
        extra.any(
          (p) => p.$1 >= 343 && p.$1 <= 346 && p.$2 >= 110 && p.$2 <= 140,
        ),
        isTrue,
      );
      expect(
        extra.any(
          (p) => p.$1 >= 462 && p.$1 <= 465 && p.$2 >= 110 && p.$2 <= 140,
        ),
        isTrue,
      );
    });

    testWidgets('a segno sits above the staff at its beat', (tester) async {
      final base = await _render(tester, _painter());
      final marked = await _render(
        tester,
        _painter(navigation: [const StaffNavigation(4, NavigationKind.segno)]),
      );
      final extra = _extraPixels(base, marked);
      expect(extra, isNotEmpty);
      // Centred on x 360: origin 336.3, width 0.654 em = 47 px; baseline y
      // 120, ink rises 3.48 sp = 70 px above it.
      expect(extra.every((p) => p.$2 < 160), isTrue);
      expect(extra.every((p) => p.$1 > 330 && p.$1 < 390), isTrue);
    });

    testWidgets('D.C. al Fine text sits above the staff at its beat', (
      tester,
    ) async {
      final base = await _render(tester, _painter());
      final marked = await _render(
        tester,
        _painter(
          navigation: [const StaffNavigation(4, NavigationKind.dcAlFine)],
        ),
      );
      final extra = _extraPixels(base, marked);
      expect(extra, isNotEmpty);
      // The label box is wide under the test font and runs off the canvas:
      // check only the start and the height band above the staff.
      expect(extra.every((p) => p.$2 < 160 && p.$2 > 40), isTrue);
      expect(extra.every((p) => p.$1 >= 355), isTrue);
    });

    testWidgets('signature change draws a measure line and new signature', (
      tester,
    ) async {
      final base = await _render(tester, _painter());
      final marked = await _render(
        tester,
        _painter(
          signatureChanges: const [
            StaffSignatureChange(
              beat: 4,
              keyFifths: 1,
              numerator: 3,
              denominator: 4,
            ),
          ],
          measureStarts: const [0, 4, 7],
        ),
      );
      expect(_extraPixels(base, marked), isNotEmpty);
    });
  });
}

const _width = 600;
const _height = 400;

StaffPainter _painter({
  List<StaffRepeatBarline> repeatBarlines = const [],
  List<StaffVolta> voltas = const [],
  List<StaffNavigation> navigation = const [],
  List<StaffSignatureChange> signatureChanges = const [],
  List<double> measureStarts = const [],
}) => StaffPainter(
  notes: const [],
  playheadBeat: ValueNotifier<double>(0),
  pixelsPerBeat: 60,
  lineRatio: 0.2,
  staves: Staves.treble,
  playheadColor: const Color(0xFFFF0000),
  inkColor: const Color(0xFF000000),
  repeatBarlines: repeatBarlines,
  voltas: voltas,
  navigation: navigation,
  signatureChanges: signatureChanges,
  measureStarts: measureStarts,
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
