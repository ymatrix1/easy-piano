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
}
