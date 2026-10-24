import 'package:easy_piano/ui/staff/dynamics_layout.dart';
import 'package:flutter/material.dart';
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

  test('ascent and descent follow the glyph bboxes', () {
    expect(DynamicsLayout.ascentSp('p'), closeTo(1.096, 1e-9));
    expect(DynamicsLayout.ascentSp('mf'), closeTo(1.776, 1e-9));
    expect(DynamicsLayout.descentSp('p'), closeTo(0.568, 1e-9));
    expect(DynamicsLayout.descentSp('f'), closeTo(0.608, 1e-9));
    expect(DynamicsLayout.descentSp('mp'), closeTo(0.568, 1e-9));
    expect(DynamicsLayout.boxHeightSp('mf'), closeTo(1.776 + 0.608, 1e-9));
  });

  group('notehead centre (centerOnNotehead)', () {
    test('filled and whole noteheads: half their bbox width', () {
      expect(
        DynamicsLayout.noteheadCentreSp(whole: false),
        closeTo(0.59, 1e-9),
      );
      expect(
        DynamicsLayout.noteheadCentreSp(whole: true),
        closeTo(0.844, 1e-9),
      );
    });

    test('dynamic text is centred on the notehead', () {
      expect(DynamicsLayout.dynamicLeft(centreX: 50, width: 10), 45);
    });
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

  group('nominal placement below the bottom staff line', () {
    test('dynamic top is dynamicsPosBelow (2 spaces) below the line', () {
      expect(
        DynamicsLayout.dynamicNominalTop(bottomStaffY: 200, space: space),
        200 + 2 * space,
      );
    });

    test('hairpin centre is hairpinPosBelow (1.75 spaces) below the line', () {
      expect(
        DynamicsLayout.hairpinCentreY(bottomStaffY: 200, space: space),
        200 + 1.75 * space,
      );
      // Its box is hairpinHeight + line width tall, centred on that line.
      expect(
        DynamicsLayout.hairpinNominalTop(bottomStaffY: 200, space: space),
        200 + 1.75 * space - DynamicsLayout.hairpinBoxSp * space / 2,
      );
    });
  });

  group('clearBelow (autoplace below)', () {
    test('a box clear of the obstacle stays where it is', () {
      // Obstacle top 50; box 40..45 with minDist 2 ends at 47 < 50.
      final top = DynamicsLayout.clearBelow(
        top: 40,
        height: 5,
        x0: 5,
        x1: 10,
        minDist: 2,
        obstacles: const [Rect.fromLTRB(0, 50, 20, 60)],
      );
      expect(top, 40);
    });

    test('a box that would overlap is pushed below obstacle + minDist', () {
      final top = DynamicsLayout.clearBelow(
        top: 46,
        height: 5,
        x0: 5,
        x1: 10,
        minDist: 2,
        obstacles: const [Rect.fromLTRB(0, 50, 20, 60)],
      );
      expect(top, 60 + 2);
    });

    test('obstacles horizontally clear of the box are ignored', () {
      final top = DynamicsLayout.clearBelow(
        top: 46,
        height: 5,
        x0: 30,
        x1: 40,
        minDist: 2,
        obstacles: const [Rect.fromLTRB(0, 50, 20, 60)],
      );
      expect(top, 46);
    });

    test('obstacles above the box never move it up', () {
      final top = DynamicsLayout.clearBelow(
        top: 70,
        height: 5,
        x0: 5,
        x1: 10,
        minDist: 2,
        obstacles: const [Rect.fromLTRB(0, 50, 20, 60)],
      );
      expect(top, 70);
    });
  });

  group('centredTop (centerItemGroup)', () {
    test('equal clearance above and below the centred box', () {
      // Free band 100..130, box 10, minDist 5: free = 10, top = 100+5+5.
      final top = DynamicsLayout.centredTop(
        upperBottom: 100,
        lowerTop: 130,
        height: 10,
        minDist: 5,
      );
      expect(top, 110);
      // spaceAbove = top - upper - minDist; spaceBelow = lower - (top+h) - minDist.
      expect(top - 100 - 5, closeTo(130 - (top + 10) - 5, 1e-9));
    });

    test(
      'a box taller than the band is still centred (MuseScore moves it)',
      () {
        final top = DynamicsLayout.centredTop(
          upperBottom: 100,
          lowerTop: 105,
          height: 10,
          minDist: 2,
        );
        // free = 105 - 100 - 10 - 4 = -9, top = 100 + 2 - 4.5 = 97.5.
        expect(top, closeTo(97.5, 1e-9));
        expect(top - 100 - 2, closeTo(105 - (top + 10) - 2, 1e-9));
      },
    );
  });

  test('gapEdges takes the nearest obstacle on each side of the gap', () {
    final (upper, lower) = DynamicsLayout.gapEdges(
      x0: 0,
      x1: 10,
      gapMidY: 115,
      obstacles: const [
        Rect.fromLTRB(5, 102, 6, 110), // stem hanging from the treble staff
        Rect.fromLTRB(5, 120, 6, 125), // stem rising to the bass staff
        Rect.fromLTRB(50, 104, 60, 108), // out of x range: ignored
      ],
      upperDefault: 100,
      lowerDefault: 130,
    );
    expect(upper, 110);
    expect(lower, 120);
  });

  group('barlineShift (manageBarlineCollisions)', () {
    // Thin barline half width 0.08 sp; minBarLineDistance 0.25 sp = 2.5 at 10.
    const half = 0.16 * space / 2;
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
      final dx = DynamicsLayout.barlineShift(
        left: 100,
        right: 110,
        barlineXs: const [112],
        space: space,
      );
      expect(dx, closeTo((112 - half) - 110 - gap, 1e-9));
    });

    test('barline at the note itself moves the dynamic right of it', () {
      final dx = DynamicsLayout.barlineShift(
        left: 100,
        right: 110,
        barlineXs: const [100],
        space: space,
      );
      expect(dx, closeTo(half + gap, 1e-9));
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

  group('stackGroup (centerItemGroup convergence)', () {
    test('items that fit keep their natural tops', () {
      final (rel, height) = DynamicsLayout.stackGroup(
        natural: const [100, 200],
        heights: const [10, 10],
        gaps: const [5, 5],
      );
      expect(rel, [0, 100]);
      expect(height, 110);
    });

    test('overlapping items are packed one under the other', () {
      final (rel, height) = DynamicsLayout.stackGroup(
        natural: const [100, 102, 104],
        heights: const [10, 10, 10],
        gaps: const [5, 5, 5],
      );
      // Sorted by natural top: 0, then 10+5 = 15, then 25+5 = 30.
      expect(rel, [0, 15, 30]);
      expect(height, 40);
    });
  });
}
