import 'dart:convert';
import 'dart:io';

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

  test('ped ... ped-up makes one released pedal span', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': 'C4:4 D4:4 E4:4 F4:4', 'LH': '{ped} C3:2 {ped-up} C3:2'},
      ]),
    );
    expect(m.pedals, hasLength(1));
    final p = m.pedals.single;
    expect(p.startBeat, 0);
    expect(p.endBeat, 2);
    expect(p.released, isTrue);
    expect(p.changeBeats, isEmpty);
  });

  test('ped while already down is a change at that beat', () {
    final m = SongMarksParser.parse(
      _song([
        {
          'RH': 'C4:4 D4:4 E4:4 F4:4',
          'LH': '{ped} C3:4 {ped} C3:4 {ped-up} C3:4',
        },
      ]),
    );
    expect(m.pedals, hasLength(1));
    expect(m.pedals.single.changeBeats, [1]);
    expect(m.pedals.single.endBeat, 2);
  });

  test('pedal left down runs to the end of the song, unreleased', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': 'C4:4 D4:4 E4:4 F4:4', 'LH': '{ped} C3:1'},
        {'RH': 'C4:1', 'LH': 'C3:1'},
      ]),
    );
    expect(m.pedals.single.endBeat, 8);
    expect(m.pedals.single.released, isFalse);
  });

  test('a pedal pressed and lifted on the same beat draws nothing', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': 'C4:4 D4:4 E4:4 F4:4', 'LH': 'C3:4 {ped} {ped-up} C3:4 C3:2'},
      ]),
    );
    expect(m.pedals, isEmpty);
  });

  test(
    'content/songs/pedal-demo.json has the pedal spans it is written for',
    () {
      final json = File('../content/songs/pedal-demo.json').readAsStringSync();
      final pedals = SongMarksParser.parse(json).pedals;
      expect(pedals, hasLength(3));
      // bar 1 down, change in bar 3 (beat 8), release in bar 4 (beat 14)
      expect(pedals[0].startBeat, 0);
      expect(pedals[0].changeBeats, [8]);
      expect(pedals[0].endBeat, 14);
      expect(pedals[0].released, isTrue);
      // bar 5 down, release in bar 6 (beat 22)
      expect(pedals[1].startBeat, 16);
      expect(pedals[1].endBeat, 22);
      expect(pedals[1].released, isTrue);
      // bar 7 down, never released: runs to the end at beat 28
      expect(pedals[2].startBeat, 24);
      expect(pedals[2].endBeat, 28);
      expect(pedals[2].released, isFalse);
    },
  );

  test('ped directive in both hands is kept once', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': '{ped} C4:2 {ped-up} D4:2', 'LH': '{ped} C3:2 {ped-up} C3:2'},
      ]),
    );
    expect(m.pedals, hasLength(1));
    expect(m.pedals.single.changeBeats, isEmpty);
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
