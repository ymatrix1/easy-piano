import 'dart:math' as math;

import 'piano_synth.dart';

/// One app-played note of a play-along companion (never graded).
class BackingNote {
  const BackingNote(this.pitch, this.beat, this.beats, this.part);

  /// MIDI pitch; for `DRUMS` a General MIDI percussion number.
  final int pitch;
  final double beat;
  final double beats;

  /// Score part: `ACC`, `DRUMS`, `BASS`, `PAD`, `CHOIR`, or a hand part.
  final String part;
}

/// How an app-played note is performed: when (beats, after humanizing),
/// for how long, and how hard.
class Performed {
  const Performed(this.note, this.beat, this.beats, this.velocity);
  final BackingNote note;
  final double beat;
  final double beats;
  final int velocity;
}

/// Base velocity per part (and per drum voice).
const _baseVelocity = {'ACC': 64, 'BASS': 86, 'PAD': 70, 'CHOIR': 72};
const _drumVelocity = {36: 104, 38: 94, 42: 68, 46: 74, 49: 96};

/// Largest humanize offset per part, in milliseconds. Kept to a few ms so
/// the band still locks to the audio clock (rule 7); graded targets are
/// never sent through here.
const _humanizeMs = {'DRUMS': 5.0, 'BASS': 4.0, 'PAD': 8.0, 'CHOIR': 8.0};
const _accHumanizeMs = 3.0;

/// Metric accent in velocity steps: downbeat strongest, then the mid-bar
/// beat, other beats, and off-beat subdivisions softest.
int metricAccent(double beat, int beatsPerBar) {
  final inBar = beat % beatsPerBar;
  const eps = 1e-6;
  if (inBar < eps) return 10;
  final onBeat = (inBar - inBar.roundToDouble()).abs() < eps;
  if (!onBeat) return -8;
  if (beatsPerBar == 4 && (inBar - 2).abs() < eps) return 4;
  return 0;
}

/// Phrase arc: notes swell toward the middle of each [phraseBars]-bar phrase
/// and ease off at its end, up to [depth] velocity steps.
int phraseShape(
  double beat,
  int beatsPerBar, {
  int phraseBars = 4,
  int depth = 8,
}) {
  final phraseBeats = phraseBars * beatsPerBar;
  final pos = (beat % phraseBeats) / phraseBeats;
  return (depth * math.sin(math.pi * pos) - depth / 2).round();
}

/// A repeatable pseudo-random offset in [-1, 1] for a note, so the same song
/// is humanized the same way every time (no flaky tests or A/B surprises).
double _jitter(BackingNote n, int index) {
  var h = n.pitch * 73856093 ^ (n.beat * 1000).round() * 19349663 ^ index;
  h = (h ^ (h >> 13)) * 1274126177;
  return ((h & 0xffff) / 0xffff) * 2 - 1;
}

/// Turns score notes into performed notes: metric and phrase velocity,
/// humanized timing on band parts, legato bass and pedalled `ACC` chords.
List<Performed> perform(
  List<BackingNote> notes, {
  required int beatsPerBar,
  required double msPerBeat,
}) {
  // Next onset per part, for pedalling and legato.
  final onsets = <String, List<double>>{};
  for (final n in notes) {
    (onsets[n.part] ??= []).add(n.beat);
  }
  for (final l in onsets.values) {
    l.sort();
  }
  double? nextOnset(BackingNote n) {
    for (final b in onsets[n.part]!) {
      if (b > n.beat + 1e-6) return b;
    }
    return null;
  }

  final chordAt = <(String, double), int>{};
  for (final n in notes) {
    chordAt[(n.part, n.beat)] = (chordAt[(n.part, n.beat)] ?? 0) + 1;
  }
  final lastBeat = notes.isEmpty
      ? 0.0
      : notes.map((n) => n.beat).reduce(math.max);

  final out = <Performed>[];
  for (var i = 0; i < notes.length; i++) {
    final n = notes[i];
    final base = n.part == 'DRUMS'
        ? _drumVelocity[n.pitch] ?? 80
        : _baseVelocity[n.part] ?? 64;
    var vel = base + metricAccent(n.beat, beatsPerBar);
    // Sustained parts don't accent; they breathe with the phrase instead.
    if (n.part == 'PAD' || n.part == 'CHOIR') vel = base;
    if (n.part != 'DRUMS') vel += phraseShape(n.beat, beatsPerBar);
    if (n.beat >= lastBeat - 1e-6 && n.part != 'DRUMS') vel -= 6;

    var beats = n.beats;
    final next = nextOnset(n);
    if (n.part == 'ACC' && (chordAt[(n.part, n.beat)] ?? 0) > 1) {
      // Pedal: hold the chord until the next one, up to a bar.
      if (next != null) {
        beats = math.max(
          beats,
          math.min(next - n.beat, beatsPerBar.toDouble()),
        );
      }
    } else if (n.part == 'BASS') {
      beats *= 0.92;
    } else if (n.part == 'ACC' || n.part == 'RH' || n.part == 'LH') {
      beats *= 0.95;
    }

    final maxMs = n.part == 'ACC' ? _accHumanizeMs : _humanizeMs[n.part] ?? 0;
    final shift = maxMs * _jitter(n, i) / msPerBeat;
    out.add(Performed(n, n.beat + shift, beats, vel.clamp(1, 127)));
  }
  return out;
}

/// Schedules the performed companion notes at or after [fromBeat] on
/// [synth]. [inSec] turns song beats into seconds from now (the audio clock).
void scheduleBacking(
  PianoSynth synth,
  List<BackingNote> notes, {
  required double fromBeat,
  required double msPerBeat,
  required int beatsPerBar,
  required double Function(double beat) inSec,
}) {
  final secPerBeat = msPerBeat / 1000;
  for (final p in perform(
    notes,
    beatsPerBar: beatsPerBar,
    msPerBeat: msPerBeat,
  )) {
    final n = p.note;
    if (n.beat < fromBeat) continue;
    final at = inSec(p.beat);
    final dur = p.beats * secPerBeat;
    switch (n.part) {
      case 'DRUMS':
        synth.drum(n.pitch, at, velocity: p.velocity);
      case 'BASS':
        synth.bass(n.pitch, at, dur, velocity: p.velocity);
      case 'CHOIR':
        synth.choir(n.pitch, at, dur, velocity: p.velocity);
      case 'PAD':
        synth.pad(n.pitch, at, dur, velocity: p.velocity);
      default:
        synth.schedule(
          n.pitch,
          at,
          dur,
          velocity: p.velocity,
          force: true,
          part: n.part == 'ACC' ? 'ACC' : 'piano',
        );
    }
  }
}
