import 'dart:ui';

import 'package:easy_piano/ui/staff/pedal_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const space = 10.0;

  group('glyphs', () {
    test('Ped. and * are the SMuFL pedal glyphs', () {
      expect(PedalLayout.pedGlyph, '\uE650');
      expect(PedalLayout.starGlyph, '\uE655');
    });
  });

  group('lineY', () {
    test('sits at pedalPosBelow with nothing in the way', () {
      final y = PedalLayout.lineY(
        bottomStaffY: 100,
        space: space,
        x0: 0,
        x1: 200,
        obstacles: const [],
      );
      expect(y, closeTo(100 + 2.5 * space, 1e-9));
    });

    test('moves down past a notehead whose box reaches into the hook', () {
      // Nominal hook box is [113, 125]. The obstacle [110, 130] overlaps it, so
      // the box moves to 130 + minDist (5) = 135 and the line to 135 + 12.
      final y = PedalLayout.lineY(
        bottomStaffY: 100,
        space: space,
        x0: 0,
        x1: 50,
        obstacles: const [Rect.fromLTRB(0, 110, 50, 130)],
      );
      expect(y, closeTo(147, 1e-9));
    });

    test('ignores an obstacle that is horizontally clear', () {
      final y = PedalLayout.lineY(
        bottomStaffY: 100,
        space: space,
        x0: 0,
        x1: 50,
        obstacles: const [Rect.fromLTRB(60, 110, 90, 130)],
      );
      expect(y, closeTo(100 + 2.5 * space, 1e-9));
    });
  });

  group('geometry', () {
    test('Ped. starts half a space before the note, line after the glyph', () {
      final g = PedalLayout.geometry(
        space: space,
        lineY: 130,
        downX: 100,
        endPointX: 300,
        released: true,
        changeX: const [],
        pedWidth: 20,
      );
      expect(g.pedX, closeTo(95, 1e-9));
      expect(g.startX, closeTo(95 + 20 + 2, 1e-9));
      expect(g.endX, 300);
      expect(g.starX, closeTo(300 + 1, 1e-9));
    });

    test('keeps only change notches inside the span, sorted', () {
      final g = PedalLayout.geometry(
        space: space,
        lineY: 130,
        downX: 100,
        endPointX: 300,
        released: true,
        changeX: const [250, 50, 150, 400],
        pedWidth: 20,
      );
      expect(g.notchX, [150, 250]);
    });
  });

  group('strokes', () {
    test('released span with no change: one line and one release hook', () {
      final g = PedalLayout.geometry(
        space: space,
        lineY: 130,
        downX: 100,
        endPointX: 300,
        released: true,
        changeX: const [],
        pedWidth: 20,
      );
      final s = PedalLayout.strokes(g, space: space);
      expect(s, hasLength(2));
      expect(s[0].first, Offset(g.startX, 130));
      expect(s[0].last, Offset(300, 130));
      // Vertical hook up from the release point, 1.2 sp high.
      expect(s[1], [Offset(300, 130), Offset(300, 130 - 12)]);
    });

    test('a change breaks the line into a /\\ notch', () {
      final g = PedalLayout.geometry(
        space: space,
        lineY: 130,
        downX: 100,
        endPointX: 300,
        released: true,
        changeX: const [200],
        pedWidth: 20,
      );
      final s = PedalLayout.strokes(g, space: space);
      // line, notch, line, hook
      expect(s, hasLength(4));
      final notch = s[1];
      expect(notch, hasLength(3));
      expect(notch[0].dy, 130);
      expect(notch[1], Offset(200, 130 - 6));
      expect(notch[2].dy, 130);
      expect(s[2].first.dx, closeTo(200 + 3.5, 1e-9));
    });

    test('open span runs to the song end with no release hook', () {
      final g = PedalLayout.geometry(
        space: space,
        lineY: 130,
        downX: 100,
        endPointX: 300,
        released: false,
        changeX: const [],
        pedWidth: 20,
      );
      final s = PedalLayout.strokes(g, space: space);
      expect(s, hasLength(1));
      expect(s.single.last, Offset(300, 130));
    });
  });
}
