import 'dart:convert';
import 'dart:io';

import 'package:easy_piano/ui/staff/arpeggio_layout.dart';
import 'package:easy_piano/ui/staff/dynamics_layout.dart';
import 'package:easy_piano/ui/staff/ornament_layout.dart';
import 'package:easy_piano/ui/staff/ottava_layout.dart';
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

  test('signature changes set variable measure starts and draw keys', () {
    final json = jsonEncode({
      'time': '4/4',
      'key': 'C',
      'changes': [
        {'bar': 2, 'time': '3/4', 'key': 'G'},
      ],
      'bars': [
        {'RH': 'C4:1'},
        {'RH': 'F#4:2.'},
        {'RH': 'G4:2.'},
      ],
    });
    final marks = SongMarksParser.parse(json);
    expect(marks.signatureChanges, hasLength(1));
    expect(marks.signatureChanges.single.beat, 4);
    expect(marks.signatureChanges.single.keyFifths, 1);
    expect(
      (
        marks.signatureChanges.single.numerator,
        marks.signatureChanges.single.denominator,
      ),
      (3, 4),
    );
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

  group('repeats, voltas and navigation', () {
    test('tie directives preserve source noteheads for engraving', () {
      final m = SongMarksParser.parse(
        _song([
          {'RH': 'C4:2 {tie} r:2', 'LH': 'C3:1'},
          {'RH': 'C4:2 D4:4 E4:4', 'LH': 'C3:1'},
        ]),
      );
      expect(m.ties, hasLength(1));
      expect(m.ties.single.startBeat, 0);
      expect(m.ties.single.endBeat, 4);
      expect(m.ties.single.pitch, 60);
      expect(m.ties.single.continuationBeats, 2);
    });

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

    test('Fine, To Coda and all D.C./D.S. directions are retained', () {
      final m = SongMarksParser.parse(
        _song([
          {
            'RH': '{fine} C4:4 {to_coda} D4:4 {dc_al_coda} E4:4 {ds_al_fine} F4:4',
            'LH': 'C3:1',
          },
        ]),
      );
      expect(m.navigation.map((n) => n.kind), [
        NavigationKind.fine,
        NavigationKind.toCoda,
        NavigationKind.dcAlCoda,
        NavigationKind.dsAlFine,
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
          {
            'RH': '{repeat} {segnÔö£Ôöé} {volta} C4:4 D4:4 E4:4 F4:4',
            'LH': 'C3:1',
          },
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

  test('ornament directives mark the chord at their beat, per hand', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': '{trill} C4:2 {turn} D4:2', 'LH': '{mordent} C3:1'},
      ]),
    );
    expect(m.ornaments, hasLength(3));
    final rh = m.ornaments.where((o) => !o.leftHand).toList();
    expect(rh.map((o) => o.beat), [0, 2]);
    expect(rh.map((o) => o.kind), [OrnamentKind.trill, OrnamentKind.turn]);
    final lh = m.ornaments.where((o) => o.leftHand).single;
    expect(lh.beat, 0);
    expect(lh.kind, OrnamentKind.mordent);
  });

  test('ornament in RH and RH2 at one beat is kept once', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': '{trill} C4:4 D4:4 E4:4 F4:4', 'RH2': '{trill} G3:2 G3:2'},
      ]),
    );
    expect(m.ornaments, hasLength(1));
  });

  test('unknown or malformed ornament directives are ignored', () {
    final m = SongMarksParser.parse(
      _song([
        {
          'RH':
              '{tremolo} C4:1 {trill:"x"} D4:1 {trill } E4:1 {Trill} F4:1 '
              '{acc:H5} {acc:"H5"} {acc:"D"} {acc:"D5x"} {acc:"G10"}',
          'LH': 'C3:1',
        },
      ]),
    );
    expect(m.ornaments, isEmpty);
    expect(m.acciaccaturas, isEmpty);
    expect(m.dynamics, isEmpty);
  });

  test('an acciaccatura takes its pitch from the name, no time', () {
    final m = SongMarksParser.parse(
      _song([
        {
          'RH': '{acc:"D5"} C5:4 {acc:"F#4"} G4:4 {acc:"Bb3"} C4:2',
          'LH': 'C3:1',
        },
      ]),
    );
    expect(m.acciaccaturas.map((a) => a.beat), [0, 1, 2]);
    expect(m.acciaccaturas.map((a) => a.pitch), [74, 66, 58]);
    expect(m.acciaccaturas.map((a) => a.accidental), [null, 'sharp', 'flat']);
    expect(m.acciaccaturas.every((a) => !a.leftHand), isTrue);
  });

  test('acciaccatura names: natural sign and out-of-range pitch', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': '{acc:"Cn4"} C4:2 {acc:"C10"} D4:2', 'LH': 'C3:1'},
      ]),
    );
    expect(m.acciaccaturas, hasLength(1));
    expect(m.acciaccaturas.single.pitch, 60);
    expect(m.acciaccaturas.single.accidental, 'natural');
  });

  test(
    'ornaments on a rest are parsed; the painter draws no note for them',
    () {
      final m = SongMarksParser.parse(
        _song([
          {'RH': '{trill} r:4 C4:4 D4:2', 'LH': 'C3:1'},
        ]),
      );
      expect(m.ornaments.single.beat, 0);
    },
  );

  test('arpeggio directives set plain, up and down arpeggios per hand', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': '{arp} C4:2 {arp:up} D4:2', 'LH': '{arp:down} C3:1'},
      ]),
    );
    expect(m.arpeggios, hasLength(3));
    final rh = m.arpeggios.where((a) => !a.leftHand).toList();
    expect(rh.map((a) => a.beat), [0, 2]);
    expect(rh.map((a) => a.direction), [
      ArpeggioDirection.plain,
      ArpeggioDirection.up,
    ]);
    final lh = m.arpeggios.where((a) => a.leftHand).single;
    expect(lh.leftHand, isTrue);
    expect(lh.direction, ArpeggioDirection.down);
  });

  test('a malformed arpeggio directive is ignored', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': '{arp:sideways} C4:4 D4:4 E4:4 F4:4', 'LH': 'C3:1'},
      ]),
    );
    expect(m.arpeggios, isEmpty);
  });

  test('gliss runs from its note to the next note of the same hand', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': '{gliss} C4:2 E5:2', 'LH': 'C3:1'},
        {'RH': 'G5:1 A5:1 B5:1 C6:1', 'LH': 'C3:1'},
      ]),
    );
    expect(m.glissandi, hasLength(1));
    final g = m.glissandi.single;
    expect(g.startBeat, 0);
    expect(g.endBeat, 2);
    expect(g.leftHand, isFalse);
  });

  test('a rest does not end a glissando', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': '{gliss} C4:2 r:2 E5:4', 'LH': 'C3:1'},
      ]),
    );
    expect(m.glissandi, hasLength(1));
    // C4:2 then a 2-beat rest: the gliss ends at E5, on beat 4.
    expect(m.glissandi.single.endBeat, 4);
  });

  test('a gliss with no following note in its hand draws nothing', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': 'C4:2 {gliss}', 'LH': 'C3:1'},
      ]),
    );
    expect(m.glissandi, isEmpty);
  });

  test('the gliss start is not closed by the note sitting on its beat', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': '{gliss} C4:2 E5:2', 'LH': 'C3:1'},
      ]),
    );
    expect(m.glissandi.single.startBeat, 0);
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

  test('{ottava:"8va"} ... {ottava_end} is one spanner on the right hand', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': 'C4:4 {ottava:"8va"} D4:4 E4:4 {ottava_end} F4:4', 'LH': 'C3:1'},
      ]),
    );
    expect(m.ottavas, hasLength(1));
    final o = m.ottavas.single;
    expect(o.kind, OttavaKind.alta);
    expect(o.startBeat, 1);
    expect(o.endBeat, 3);
    expect(o.leftHand, isFalse);
  });

  test('{ottava:"8vb"} in a left-hand bar belongs to the bass staff', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': 'C4:1', 'LH': '{ottava:"8vb"} C2:4 D2:4 E2:4 {ottava_end} F2:4'},
      ]),
    );
    expect(m.ottavas, hasLength(1));
    final o = m.ottavas.single;
    expect(o.kind, OttavaKind.bassa);
    expect(o.startBeat, 0);
    expect(o.endBeat, 3);
    expect(o.leftHand, isTrue);
  });

  test('an ottava left open runs to the end of the song', () {
    final m = SongMarksParser.parse(
      _song([
        {'RH': 'C4:4 {ottava:"8va"} D4:4 E4:4 F4:4', 'LH': 'C3:1'},
        {'RH': 'C4:1', 'LH': 'C3:1'},
      ]),
    );
    expect(m.ottavas.single.endBeat, 8);
  });

  test('a new ottava start on the same hand closes the previous one', () {
    final m = SongMarksParser.parse(
      _song([
        {
          'RH':
              '{ottava:"8va"} C4:4 {ottava:"8vb"} D4:4 E4:4 {ottava_end} F4:4',
          'LH': 'C3:1',
        },
      ]),
    );
    expect(m.ottavas.map((o) => o.kind), [OttavaKind.alta, OttavaKind.bassa]);
    expect(m.ottavas[0].endBeat, 1);
    expect(m.ottavas[1].startBeat, 1);
    expect(m.ottavas[1].endBeat, 3);
  });

  test('ottava events of the two hands do not close each other', () {
    final m = SongMarksParser.parse(
      _song([
        {
          'RH': '{ottava:"8va"} C5:4 D5:4 E5:4 {ottava_end} F5:4',
          'LH': '{ottava:"8vb"} C2:4 D2:4 E2:4 {ottava_end} F2:4',
        },
      ]),
    );
    expect(m.ottavas, hasLength(2));
    final rh = m.ottavas.firstWhere((o) => !o.leftHand);
    final lh = m.ottavas.firstWhere((o) => o.leftHand);
    expect(rh.kind, OttavaKind.alta);
    expect(rh.endBeat, 3);
    expect(lh.kind, OttavaKind.bassa);
    expect(lh.endBeat, 3);
  });

  test('the same ottava in both hands is kept once per hand', () {
    final m = SongMarksParser.parse(
      _song([
        {
          'RH': '{ottava:"8va"} C5:4 D5:4 {ottava_end} E5:4',
          'LH': '{ottava:"8va"} C4:4 D4:4 {ottava_end} E4:4',
        },
      ]),
    );
    expect(m.ottavas, hasLength(2));
    expect(m.ottavas.where((o) => o.leftHand), hasLength(1));
  });

  test('unknown ottava text is ignored; zero-length spanners draw nothing', () {
    final m = SongMarksParser.parse(
      _song([
        {
          'RH': '{ottava:"15ma"} C4:4 {ottava:"8va"} {ottava_end} D4:4 E4:4',
          'LH': 'C3:1',
        },
      ]),
    );
    expect(m.ottavas, isEmpty);
  });

  test('ottavas do not change dynamics or hairpins', () {
    final m = SongMarksParser.parse(
      _song([
        {
          'RH': '{dyn:"p"} {ottava:"8va"} C4:4 {cresc} D4:4 {ottava_end} E4:4 {end} F4:4',
          'LH': 'C3:1',
        },
      ]),
    );
    expect(m.dynamics.single.beat, 0);
    expect(m.hairpins.single.startBeat, 1);
    expect(m.hairpins.single.endBeat, 3);
    expect(m.ottavas.single.endBeat, 2);
  });

  test('malformed JSON gives no ottavas', () {
    expect(SongMarksParser.parse('not json').ottavas, isEmpty);
    expect(SongMarks.empty.ottavas, isEmpty);
  });
}
