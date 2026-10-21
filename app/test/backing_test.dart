import 'package:easy_piano/audio/backing.dart';
import 'package:easy_piano/audio/piano_synth.dart';
import 'package:flutter_test/flutter_test.dart';

class _Call {
  _Call(this.kind, this.pitch, this.at, this.dur, this.velocity, [this.part]);
  final String kind;
  final int pitch;
  final double at;
  final double dur;
  final int velocity;
  final String? part;
}

class _FakeSynth implements PianoSynth {
  final calls = <_Call>[];

  @override
  void drum(int gmPitch, double startSec, {int velocity = 80}) =>
      calls.add(_Call('drum', gmPitch, startSec, 0, velocity));

  @override
  void bass(int pitch, double startSec, double durSec, {int velocity = 80}) =>
      calls.add(_Call('bass', pitch, startSec, durSec, velocity));

  @override
  void pad(int pitch, double startSec, double durSec, {int velocity = 80}) =>
      calls.add(_Call('pad', pitch, startSec, durSec, velocity));

  @override
  void choir(int pitch, double startSec, double durSec, {int velocity = 80}) =>
      calls.add(_Call('choir', pitch, startSec, durSec, velocity));

  @override
  void schedule(
    int pitch,
    double startSec,
    double durSec, {
    int velocity = 80,
    bool force = false,
    String part = 'piano',
  }) => calls.add(_Call('piano', pitch, startSec, durSec, velocity, part));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('metric accent: downbeat > beat 3 > other beats > off-beats', () {
    expect(metricAccent(0, 4), greaterThan(metricAccent(2, 4)));
    expect(metricAccent(2, 4), greaterThan(metricAccent(1, 4)));
    expect(metricAccent(1, 4), greaterThan(metricAccent(1.5, 4)));
    expect(metricAccent(3, 3), metricAccent(0, 3));
  });

  test('phrase shape swells mid-phrase and eases at the edges', () {
    expect(phraseShape(8, 4), greaterThan(phraseShape(0, 4)));
    expect(phraseShape(8, 4), greaterThan(phraseShape(15.5, 4)));
  });

  test('humanize is small, repeatable and never on hand parts', () {
    const notes = [
      BackingNote(36, 0, 1, 'DRUMS'),
      BackingNote(42, 0.5, 0.5, 'DRUMS'),
      BackingNote(36, 1, 1, 'BASS'),
      BackingNote(60, 1, 1, 'RH'),
    ];
    const msPerBeat = 500.0;
    final a = perform(notes, beatsPerBar: 4, msPerBeat: msPerBeat);
    final b = perform(notes, beatsPerBar: 4, msPerBeat: msPerBeat);
    for (var i = 0; i < notes.length; i++) {
      expect(a[i].beat, b[i].beat);
      final ms = (a[i].beat - notes[i].beat).abs() * msPerBeat;
      expect(ms, lessThanOrEqualTo(8));
    }
    expect(a[3].beat, notes[3].beat);
  });

  test('ACC chords are pedalled to the next chord; bass is legato', () {
    const notes = [
      BackingNote(48, 0, 1, 'ACC'),
      BackingNote(52, 0, 1, 'ACC'),
      BackingNote(55, 0, 1, 'ACC'),
      BackingNote(50, 2, 1, 'ACC'),
      BackingNote(36, 0, 1, 'BASS'),
    ];
    final p = perform(notes, beatsPerBar: 4, msPerBeat: 500);
    expect(p[0].beats, 2);
    expect(p[3].beats, closeTo(0.95, 1e-9));
    expect(p[4].beats, closeTo(0.92, 1e-9));
  });

  test('scheduleBacking routes parts and skips notes before fromBeat', () {
    final synth = _FakeSynth();
    scheduleBacking(
      synth,
      const [
        BackingNote(36, 0, 1, 'DRUMS'),
        BackingNote(40, 1, 1, 'BASS'),
        BackingNote(60, 1, 2, 'PAD'),
        BackingNote(64, 1, 2, 'CHOIR'),
        BackingNote(48, 1, 1, 'ACC'),
        BackingNote(72, 0.5, 1, 'ACC'),
      ],
      fromBeat: 1,
      msPerBeat: 500,
      beatsPerBar: 4,
      inSec: (b) => b * 0.5,
    );
    expect(synth.calls.map((c) => c.kind), ['bass', 'pad', 'choir', 'piano']);
    expect(synth.calls.last.part, 'ACC');
    for (final c in synth.calls) {
      expect(c.at, closeTo(0.5, 0.01));
      expect(c.velocity, inInclusiveRange(1, 127));
    }
  });
}
