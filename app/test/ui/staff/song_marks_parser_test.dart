import 'dart:convert';

import 'package:easy_piano/ui/staff/dynamics_layout.dart';
import 'package:easy_piano/ui/staff/repeat_layout.dart';
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

  group('repeats, voltas and navigation', () {
    test('repeat start and end sit on the bar lines they are written on', () {
      final m = SongMarksParser.parse(
        _song([
          {'RH': '{repeat_start} C4:4 D4:4 E4:4 F4:4', 'LH': 'C3:1'},
          {'RH': 'C4:4 D4:4 E4:4 F4:4 {repeat_end}', 'LH': 'C3:1 {repeat_end}'},
        ]),
      );
      expect(m.repeatBarlines, hasLength(2));
      expect(m.repeatBarlines[0].beat, 0);
      expect(m.repeatBarlines[0].start, isTrue);
      expect(m.repeatBarlines[0].end, isFalse);
      expect(m.repeatBarlines[1].beat, 8);
      expect(m.repeatBarlines[1].end, isTrue);
      expect(m.repeatBarlines[1].start, isFalse);
    });

    test('repeat start and end on one bar line make a double repeat', () {
      final m = SongMarksParser.parse(
        _song([
          {'RH': 'C4:4 D4:4 E4:4 F4:4 {repeat_end}', 'LH': 'C3:1'},
          {'RH': '{repeat_start} C4:4 D4:4 E4:4 F4:4', 'LH': 'C3:1'},
        ]),
      );
      expect(m.repeatBarlines, hasLength(1));
      expect(m.repeatBarlines.single.beat, 4);
      expect(m.repeatBarlines.single.start, isTrue);
      expect(m.repeatBarlines.single.end, isTrue);
    });

    test('a directive off the bar line is ignored', () {
      final m = SongMarksParser.parse(
        _song([
          {'RH': 'C4:4 {repeat_start} D4:4 E4:4 F4:4', 'LH': 'C3:1'},
          {'RH': 'C4:4 {volta: [1]} D4:4 E4:4 F4:4', 'LH': 'C3:1'},
        ]),
      );
      expect(m.repeatBarlines, isEmpty);
      expect(m.voltas, isEmpty);
    });

    test('first ending closed by a repeat end has a hook; second runs on', () {
      final m = SongMarksParser.parse(
        _song([
          {'RH': '{repeat_start} C4:4 D4:4 E4:4 F4:4', 'LH': 'C3:1'},
          {'RH': '{volta: [1]} C4:4 D4:4 E4:4 F4:4 {repeat_end}', 'LH': 'C3:1'},
          {'RH': '{volta: [2]} C4:4 D4:4 E4:4 F4:4', 'LH': 'C3:1'},
        ]),
      );
      expect(m.voltas, hasLength(2));
      final first = m.voltas[0];
      expect(first.number, 1);
      expect(first.startBeat, 4);
      expect(first.endBeat, 8);
      expect(first.closedEnd, isTrue);
      final second = m.voltas[1];
      expect(second.number, 2);
      expect(second.startBeat, 8);
      // Left open: runs to the end of the song, no hook.
      expect(second.endBeat, 12);
      expect(second.closedEnd, isFalse);
    });

    test('a volta closed by volta_end has no hook', () {
      final m = SongMarksParser.parse(
        _song([
          {'RH': '{volta: [2]} C4:4 D4:4 E4:4 F4:4', 'LH': 'C3:1'},
          {'RH': '{volta_end} C4:4 D4:4 E4:4 F4:4', 'LH': 'C3:1'},
        ]),
      );
      expect(m.voltas.single.startBeat, 0);
      expect(m.voltas.single.endBeat, 4);
      expect(m.voltas.single.closedEnd, isFalse);
    });

    test('a volta number other than 1 or 2 is ignored', () {
      final m = SongMarksParser.parse(
        _song([
          {'RH': '{volta: [3]} C4:4 D4:4 E4:4 F4:4', 'LH': 'C3:1'},
          {'RH': '{volta: [1, 2]} C4:4 D4:4 E4:4 F4:4', 'LH': 'C3:1'},
          {'RH': '{volta:1} C4:4 D4:4 E4:4 F4:4', 'LH': 'C3:1'},
        ]),
      );
      expect(m.voltas, isEmpty);
    });

    test('segno, coda and jump marks sit at their beat, on any beat', () {
      final m = SongMarksParser.parse(
        _song([
          {'RH': 'C4:4 {segno} D4:4 E4:4 F4:4', 'LH': 'C3:1'},
          {'RH': 'C4:4 {coda} D4:4 {dc_al_fine} E4:4 F4:4', 'LH': 'C3:1'},
          {'RH': 'C4:4 {ds_al_coda} D4:4 E4:4 F4:4', 'LH': 'C3:1'},
        ]),
      );
      expect(m.navigation.map((n) => (n.beat, n.kind)), [
        (1.0, NavigationKind.segno),
        (5.0, NavigationKind.coda),
        (6.0, NavigationKind.dcAlFine),
        (9.0, NavigationKind.dsAlCoda),
      ]);
    });

    test('a navigation mark in both hands is drawn once', () {
      final m = SongMarksParser.parse(
        _song([
          {'RH': '{segno} C4:4 D4:4 E4:4 F4:4', 'LH': '{segno} C3:1'},
        ]),
      );
      expect(m.navigation, hasLength(1));
    });

    test('unknown structural names are ignored', () {
      final m = SongMarksParser.parse(
        _song([
          {'RH': '{repeat} {segnó} {volta} C4:4 D4:4 E4:4 F4:4', 'LH': 'C3:1'},
        ]),
      );
      expect(m.repeatBarlines, isEmpty);
      expect(m.voltas, isEmpty);
      expect(m.navigation, isEmpty);
    });

    test('a repeat and volta in the left hand apply to the whole song', () {
      final m = SongMarksParser.parse(
        _song([
          {'RH': 'C4:4 D4:4 E4:4 F4:4', 'LH': '{repeat_start} C3:1'},
          {'RH': 'C4:4 D4:4 E4:4 F4:4', 'LH': 'C3:1 {repeat_end}'},
        ]),
      );
      expect(m.repeatBarlines.map((r) => r.beat), [0, 8]);
    });

    test('an ending with no music after its start is dropped', () {
      final m = SongMarksParser.parse(
        _song([
          {'RH': 'C4:4 D4:4 E4:4 F4:4 {volta: [1]}', 'LH': 'C3:1'},
        ]),
      );
      expect(m.voltas, isEmpty);
    });

    test('malformed input gives no structural marks', () {
      expect(SongMarksParser.parse('').repeatBarlines, isEmpty);
      expect(SongMarksParser.parse('not json').voltas, isEmpty);
      expect(SongMarksParser.parse('[]').navigation, isEmpty);
    });
  });
}
