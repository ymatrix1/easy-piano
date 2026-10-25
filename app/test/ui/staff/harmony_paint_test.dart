import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:easy_piano/ui/staff/staff_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chord and lyric painting', () {
    // flutter_test substitutes a placeholder font for unregistered families.
    // Load the real Leland for the noteheads; the chord and lyric text uses the
    // default sans font, so its boxes are wide and only the regions matter.
    setUpAll(() async {
      final bytes = await File('assets/fonts/Leland.otf').readAsBytes();
      final loader = FontLoader('Leland')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    });

    testWidgets('a chord symbol adds ink above the top staff line only', (
      tester,
    ) async {
      final base = await _render(tester, _painter(notes: _quarters));
      final marked = await _render(
        tester,
        _painter(
          notes: _quarters,
          chords: [StaffChord(4, ChordSymbol.parse('Am7')!)],
        ),
      );
      final extra = _extraPixels(base, marked);
      expect(extra, isNotEmpty);
      // The top staff line is at y = 160 (bottom line 240, four spaces up).
      // The chord sits above it, left aligned on the note at x = 360.
      expect(extra.every((p) => p.$2 < _topLineY), isTrue);
      expect(extra.every((p) => p.$1 >= _chordX - 5), isTrue);
    });

    testWidgets('a syllable with a hyphen joins the next syllable', (
      tester,
    ) async {
      final plain = await _render(
        tester,
        _painter(
          notes: _notesAt4and6,
          lyrics: const [StaffLyric(4, 'A'), StaffLyric(6, 'B')],
        ),
      );
      final hyphen = await _render(
        tester,
        _painter(
          notes: _notesAt4and6,
          lyrics: const [StaffLyric(4, 'A', hyphen: true), StaffLyric(6, 'B')],
        ),
      );
      final extra = _extraPixels(plain, hyphen);
      expect(extra, isNotEmpty);
      // Only the hyphen differs: between the centres of A (x ~372) and B
      // (x ~492), in the band of the lyric line below the staff.
      expect(extra.every((p) => p.$1 > 380 && p.$1 < 480), isTrue);
      expect(extra.every((p) => p.$2 > _lyricTopY), isTrue);
    });

    testWidgets('an extension draws a line between the two syllables', (
      tester,
    ) async {
      final plain = await _render(
        tester,
        _painter(
          notes: _notesAt4to6,
          lyrics: const [StaffLyric(4, 'A'), StaffLyric(6, 'B')],
        ),
      );
      final melisma = await _render(
        tester,
        _painter(
          notes: _notesAt4to6,
          lyrics: const [
            StaffLyric(4, 'A'),
            StaffLyric.extension(5),
            StaffLyric(6, 'B'),
          ],
        ),
      );
      final extra = _extraPixels(plain, melisma);
      expect(extra, isNotEmpty);
      // A ends at about x 386. The melisma starts 0.2 sp later and ends at the
      // right edge of the notehead of the extension (beat 5, x 420 + 23.6),
      // so it stops before B (left edge about x 480). Thin line.
      expect(extra.every((p) => p.$1 > 380 && p.$1 < 450), isTrue);
      expect(extra.map((p) => p.$2).toSet().length, lessThanOrEqualTo(3));
    });
  });
}

// Playhead at beat 0 with lineRatio 0.2 on a 600 px wide canvas: beat b sits
// at x = 120 + 60 b. Beat 4 is clear of the clef fade that masks the left part.
const _chordX = 360.0;
const _topLineY = 160.0;
const _lyricTopY = 265.0;
const _width = 600;
const _height = 400;

const _quarters = [
  StaffNote(72, 4, 1),
  StaffNote(72, 5, 1),
  StaffNote(72, 6, 1),
];
const _notesAt4and6 = [StaffNote(72, 4, 1), StaffNote(72, 6, 1)];
const _notesAt4to6 = _quarters;

StaffPainter _painter({
  required List<StaffNote> notes,
  List<StaffChord> chords = const [],
  List<StaffLyric> lyrics = const [],
}) => StaffPainter(
  notes: notes,
  playheadBeat: ValueNotifier<double>(0),
  pixelsPerBeat: 60,
  lineRatio: 0.2,
  staves: Staves.treble,
  playheadColor: const Color(0xFFFF0000),
  inkColor: const Color(0xFF000000),
  chords: chords,
  lyrics: lyrics,
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
