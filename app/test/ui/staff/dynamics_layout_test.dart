import 'package:easy_piano/ui/staff/dynamics_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const space = 10.0;

  group('glyphsFor', () {
    test('single letters map to SMuFL dynamic glyphs', () {
      expect(DynamicsLayout.glyphsFor('p'), '\uE520');
      expect(DynamicsLayout.glyphsFor('f'), '\uE522');
    });

    test('compound marks repeat or combine letter glyphs like MuseScore', () {
      expect(DynamicsLayout.glyphsFor('pp'), '\uE520\uE520');
      expect(DynamicsLayout.glyphsFor('ppp'), '\uE520\uE520\uE520');
      expect(DynamicsLayout.glyphsFor('ff'), '\uE522\uE522');
      expect(DynamicsLayout.glyphsFor('fff'), '\uE522\uE522\uE522');
      expect(DynamicsLayout.glyphsFor('mp'), '\uE521\uE520');
      expect(DynamicsLayout.glyphsFor('mf'), '\uE521\uE522');
      expect(DynamicsLayout.glyphsFor('fp'), '\uE522\uE520');
      expect(DynamicsLayout.glyphsFor('sf'), '\uE524\uE522');
      expect(DynamicsLayout.glyphsFor('sfz'), '\uE524\uE522\uE525');
    });

    test('unsupported text is rejected', () {
      expect(DynamicsLayout.glyphsFor(''), isNull);
      expect(DynamicsLayout.glyphsFor('pppp'), isNull);
      expect(DynamicsLayout.glyphsFor('fz'), isNull);
      expect(DynamicsLayout.glyphsFor('x'), isNull);
    });
  });

  test('ascent follows the tallest glyph in the mark', () {
    expect(DynamicsLayout.ascentSp('p'), closeTo(1.096, 1e-9));
    expect(DynamicsLayout.ascentSp('mf'), closeTo(1.776, 1e-9));
    expect(DynamicsLayout.ascentSp('sfz'), closeTo(1.776, 1e-9));
  });

  group('hairpin geometry (tlayout.cpp layoutHairpinSegment)', () {
    const h = 1.15 * space * 0.5; // half of hairpinHeight

    test('crescendo: tip at x1, both arms open to x2', () {
      final segs = DynamicsLayout.hairpinSegments(
        x1: 100,
        x2: 200,
        centreY: 50,
        space: space,
        kind: HairpinKind.crescendo,
      );
      expect(segs, hasLength(2));
      for (final (a, _) in segs) {
        expect(a, const Offset(100, 50));
      }
      final ends = segs.map((s) => s.$2).toList();
      expect(ends, contains(Offset(200, 50 - h)));
      expect(ends, contains(Offset(200, 50 + h)));
    });

    test('diminuendo: arms start open at x1, meet at tip x2', () {
      final segs = DynamicsLayout.hairpinSegments(
        x1: 100,
        x2: 200,
        centreY: 50,
        space: space,
        kind: HairpinKind.diminuendo,
      );
      for (final (_, b) in segs) {
        expect(b, const Offset(200, 50));
      }
      final starts = segs.map((s) => s.$1).toList();
      expect(starts, contains(Offset(100, 50 - h)));
      expect(starts, contains(Offset(100, 50 + h)));
    });

    test('shorter than one space is stretched to one space', () {
      final segs = DynamicsLayout.hairpinSegments(
        x1: 100,
        x2: 102,
        centreY: 0,
        space: space,
        kind: HairpinKind.crescendo,
      );
      expect(segs.first.$2.dx, closeTo(100 + space, 1e-9));
    });
  });

  test('hairpin sits 1.75 spaces below the bottom staff line', () {
    expect(
      DynamicsLayout.hairpinCentreY(bottomStaffY: 200, space: space),
      200 + 1.75 * space,
    );
  });

  group('dynamic placement (dynamicslayout.cpp, dynamicsPosBelow)', () {
    test('without a hairpin the baseline is 2 spaces below the staff plus the glyph ascent', () {
      final y = DynamicsLayout.dynamicBaselineY(
        bottomStaffY: 200,
        space: space,
        mark: 'p',
        hairpinOverlaps: false,
      );
      expect(y, closeTo(200 + 2 * space + 1.096 * space, 1e-9));
    });

    test('an overlapping hairpin pushes the dynamic below it', () {
      // In spaces: hairpin centre 1.75 + half of hairpinHeight 1.15.
      const hairpinBottom = 1.75 + 1.15 * 0.5;
      final y = DynamicsLayout.dynamicBaselineY(
        bottomStaffY: 200,
        space: space,
        mark: 'p',
        hairpinOverlaps: true,
      );
      expect(
        y,
        closeTo(200 + (hairpinBottom + 0.5) * space + 1.096 * space, 1e-9),
      );
      final free = DynamicsLayout.dynamicBaselineY(
        bottomStaffY: 200,
        space: space,
        mark: 'p',
        hairpinOverlaps: false,
      );
      expect(y, greaterThan(free));
    });
  });

  group('barlineShift (manageBarlineCollisions)', () {
    const gap = 0.25 * space;

    test('no barline nearby: no shift', () {
      expect(
        DynamicsLayout.barlineShift(
          left: 100,
          right: 110,
          barlineXs: const [],
          space: space,
        ),
        0,
      );
    });

    test('barline ahead that the dynamic would run into moves it left', () {
      // Right edge 110 + 2.5 gap would hit a barline at 112.
      final dx = DynamicsLayout.barlineShift(
        left: 100,
        right: 110,
        barlineXs: const [112],
        space: space,
      );
      expect(dx, closeTo(112 - 110 - gap, 1e-9));
    });

    test('barline at the note itself moves the dynamic right of it', () {
      final dx = DynamicsLayout.barlineShift(
        left: 100,
        right: 110,
        barlineXs: const [100],
        space: space,
      );
      expect(dx, closeTo(gap, 1e-9));
    });

    test('barline far enough away is ignored', () {
      expect(
        DynamicsLayout.barlineShift(
          left: 100,
          right: 110,
          barlineXs: const [200],
          space: space,
        ),
        0,
      );
    });
  });
}
