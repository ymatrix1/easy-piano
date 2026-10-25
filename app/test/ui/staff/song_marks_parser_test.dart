import 'dart:convert';

import 'package:easy_piano/ui/staff/dynamics_layout.dart';
import 'package:easy_piano/ui/staff/song_marks_parser.dart';
import 'package:flutter_test/flutter_test.dart';

String _song(List<Map<String, String>> bars, {String time = '4/4'}) =>
    jsonEncode({'time': time, 'bars': bars});

void main() {
  test('dynamic directive sets a mark at the beat it sits on', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': 'C4:4 {dyn:"p"} D4:4 E4:2', 'LH': 'C3:1'},
      ]),
    );
    expect(m.dynamics, hasLength(1));
    expect(m.dynamics.single.beat, 1);
    expect(m.dynamics.single.mark, 'p');
    expect(m.hairpins, isEmpty);
  });

  test('bars advance the beat by the time numerator', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': 'C4:4 D4:4 E4:4', 'LH': 'C3:2.'},
        {'RH': '{dyn:"mf"} C4:4 D4:4 E4:4', 'LH': 'C3:2.'},
      ], time: '3/4'),
    );
    expect(m.dynamics.single.beat, 3);
    expect(m.dynamics.single.mark, 'mf');
  });

  test('the same directive in both hands is kept once', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': '{dyn:"p"} C4:4 D4:4 E4:4 F4:4', 'LH': '{dyn:"p"} C3:1'},
      ]),
    );
    expect(m.dynamics, hasLength(1));
  });

  test('unsupported dynamic text is ignored', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': '{dyn:"pppp"} C4:4 D4:4 E4:4 F4:4', 'LH': 'C3:1'},
      ]),
    );
    expect(m.dynamics, isEmpty);
  });

  test('cresc ... end makes one crescendo hairpin', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': 'C4:4 {cresc} D4:4 E4:4 {end} F4:4', 'LH': 'C3:1'},
      ]),
    );
    expect(m.hairpins, hasLength(1));
    final h = m.hairpins.single;
    expect(h.kind, HairpinKind.crescendo);
    expect(h.startBeat, 1);
    expect(h.endBeat, 3);
  });

  test('dim hairpin closes at the next dynamic', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': '{dyn:"f"} C4:4 {dim} D4:4 E4:4 {dyn:"p"} F4:4', 'LH': 'C3:1'},
      ]),
    );
    expect(m.dynamics.map((d) => d.mark), ['f', 'p']);
    expect(m.hairpins, hasLength(1));
    expect(m.hairpins.single.kind, HairpinKind.diminuendo);
    expect(m.hairpins.single.startBeat, 1);
    expect(m.hairpins.single.endBeat, 3);
  });

  test('a hairpin left open runs to the end of the song', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': 'C4:4 {cresc} D4:4 E4:4 F4:4', 'LH': 'C3:1'},
        {'RH': 'C4:1', 'LH': 'C3:1'},
      ]),
    );
    expect(m.hairpins.single.endBeat, 8);
  });

  test('a hairpin closed on the beat it opened draws nothing', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': 'C4:4 {cresc} {end} D4:4 E4:4 F4:4', 'LH': 'C3:1'},
      ]),
    );
    expect(m.hairpins, isEmpty);
  });

  test('malformed or non-song JSON gives no marks', () {
    expect(SongMarksParser.parse('').dynamics, isEmpty);
    expect(SongMarksParser.parse('not json').dynamics, isEmpty);
    expect(SongMarksParser.parse('[]').hairpins, isEmpty);
  });

  test('a directive in the left hand belongs to the bass staff', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': 'C4:4 D4:4 E4:4 F4:4', 'LH': '{dyn:"p"} C3:1'},
        {'RH': '{cresc} C4:4 D4:4 E4:4 F4:4', 'LH': 'C3:1'},
        {'RH': '{end} C4:1', 'LH': 'C3:1'},
      ]),
    );
    expect(m.dynamics.single.leftHand, isTrue);
    expect(m.hairpins.single.leftHand, isFalse);
  });

  test('same directive in both hands stays on the treble staff', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': '{dyn:"p"} C4:4 D4:4 E4:4 F4:4', 'LH': '{dyn:"p"} C3:1'},
      ]),
    );
    expect(m.dynamics, hasLength(1));
    expect(m.dynamics.single.leftHand, isFalse);
  });

  test('chord directive sets a chord symbol at its beat', () {
    final m = SongMarksParser.parse(
      _song([
        {
          'RH': 'C4:4 {chord:"Am7"} D4:4 E4:2',
          'LH': 'A2:2 {chord:"G7/B"} C3:2',
        },
      ]),
    );
    expect(m.chords, hasLength(2));
    expect(m.chords[0].beat, 1);
    expect(m.chords[0].symbol.root, 'A');
    expect(m.chords[0].symbol.suffix, 'm7');
    expect(m.chords[0].leftHand, isFalse);
    expect(m.chords[1].beat, 2);
    expect(m.chords[1].symbol.bass, 'B');
    expect(m.chords[1].leftHand, isTrue);
  });

  test('the same chord in both hands is kept once, on the treble', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': '{chord:"C"} C4:1', 'LH': '{chord:"C"} C3:1'},
      ]),
    );
    expect(m.chords, hasLength(1));
    expect(m.chords.single.leftHand, isFalse);
  });

  test('malformed chord text is ignored', () {
    final m = SongMarksParser.parse(
      _song([
        {
          'RH': '{chord:"H"} C4:4 {chord:"c7"} D4:4 {chord:""} E4:4 {chord:"C/"} F4:4',
          'LH': 'C3:1',
        },
      ]),
    );
    expect(m.chords, isEmpty);
  });

  test('lyric directives: syllables, hyphen and extension', () {
    final m = SongMarksParser.parse(
      _song([
        {
          'RH': '{lyric:"Hel-"} C4:4 {lyric:"lo"} D4:4 {lyric:"_"} E4:2',
          'LH': 'C3:1',
        },
      ]),
    );
    expect(m.lyrics, hasLength(3));
    expect(m.lyrics[0].beat, 0);
    expect(m.lyrics[0].text, 'Hel');
    expect(m.lyrics[0].hyphen, isTrue);
    expect(m.lyrics[1].text, 'lo');
    expect(m.lyrics[1].hyphen, isFalse);
    expect(m.lyrics[2].beat, 2);
    expect(m.lyrics[2].isExtension, isTrue);
  });

  test('a lyric in the left hand is flagged for the bass staff', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': 'C4:1', 'LH': '{lyric:"la"} C3:1'},
      ]),
    );
    expect(m.lyrics.single.leftHand, isTrue);
  });

  test('malformed lyric text is ignored', () {
    final m = SongMarksParser.parse(
      _song([
        {
          'RH': '{lyric:""} C4:4 {lyric:"-"} D4:4 {lyric:"a b"} E4:4 {lyric:"x_y"} F4:4',
          'LH': 'C3:1',
        },
      ]),
    );
    expect(m.lyrics, isEmpty);
  });

  test('chords and lyrics do not end an open hairpin', () {
    final m = SongMarksParser.parse(
      _song([
        {
          'RH': 'C4:4 {cresc} {chord:"C"} D4:4 {lyric:"la"} E4:4 {end} F4:4',
          'LH': 'C3:1',
        },
      ]),
    );
    expect(m.hairpins, hasLength(1));
    expect(m.hairpins.single.startBeat, 1);
    expect(m.hairpins.single.endBeat, 3);
  });
}
