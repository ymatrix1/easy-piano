// ignore_for_file: avoid_print
// Scores NoteDetector on the fixture set from tools/mic_fixtures.py.
// Usage (from app/): dart run tool/mic_eval.dart [../tools/mic-fixtures]
// A detected note-on matches a truth note with the same pitch and an onset
// within ±50 ms; each truth note matches at most once.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_piano/input/mic/note_detector.dart';

const _tolerance = 0.05;

void main(List<String> args) {
  final paths = args.where((a) => !a.startsWith('-')).toList();
  final dir = Directory(paths.isEmpty ? '../tools/mic-fixtures' : paths.first);
  final truth = jsonDecode(
    File('${dir.path}/truth.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final groups = <String, _Score>{};
  final verbose = args.contains('-v');
  for (final entry in truth.entries) {
    final info = entry.value as Map<String, dynamic>;
    final (sr, samples) = _readWav(File('${dir.path}/${entry.key}'));
    double arg(String k, double d) => double.parse(
      args
          .firstWhere((a) => a.startsWith('--$k='), orElse: () => '=$d')
          .split('=')
          .last,
    );
    final det = NoteDetector(
      sampleRate: sr.toDouble(),
      fluxGamma: arg('gamma', 100),
      fluxRatio: arg('ratio', 1.5),
      fluxDelta: arg('delta', 3.0),
      minAttack: arg('attack', 2),
      minSustain: arg('sustain', 3),
      tonalRatio: arg('tonal', 3),
      subOctave: arg('sub', 0.8),
    );
    final notes = [
      for (final n in info['notes'] as List)
        ((n['t'] as num).toDouble(), n['pitch'] as int),
    ];
    // --mode=blind: no expected notes. score: the lesson expects the notes
    // due from 0.3 s ago to 0.6 s ahead (wait-mode cursor). wrong: it
    // expects a whole tone higher, so every played note is unexpected.
    final mode = args
        .firstWhere((a) => a.startsWith('--mode='), orElse: () => '=blind')
        .split('=')
        .last;
    final found = <DetectedNote>[];
    for (var i = 0; i < samples.length; i += 128) {
      final end = i + 128 < samples.length ? i + 128 : samples.length;
      if (mode != 'blind') {
        final now = i / sr;
        det.expected = notes.isEmpty
            // Noise-only clip: the lesson is waiting for a C major chord
            // the whole time; any detection is false, a C/E/G one would pass
            // the step without playing.
            ? const {60, 64, 67}
            : {
                for (final (t, p) in notes)
                  if (t > now - 0.3 && t <= now + 0.6)
                    mode == 'wrong' ? p + 2 : p,
              };
      }
      found.addAll(det.process(samples.sublist(i, end)));
    }
    final ons = found.where((n) => n.on).toList();
    final used = List.filled(notes.length, false);
    var phantom = 0;
    var tp = 0;
    final errs = <double>[];
    final delays = <double>[];
    final misses = <String>[];
    for (final d in ons) {
      var hit = -1;
      for (var i = 0; i < notes.length; i++) {
        if (!used[i] &&
            notes[i].$2 == d.pitch &&
            (notes[i].$1 - d.time).abs() <= _tolerance) {
          hit = i;
          break;
        }
      }
      if (hit >= 0) {
        used[hit] = true;
        tp++;
        errs.add((d.time - notes[hit].$1) * 1000);
        delays.add((d.detectedAt - notes[hit].$1) * 1000);
      } else {
        misses.add('+${d.pitch}@${d.time.toStringAsFixed(2)}');
        // Wrong mode: the lesson expected p+2 and the student played p. A
        // detected p+2 would pass the step without it being played.
        if (mode == 'wrong' &&
            notes.any(
              (n) => n.$2 + 2 == d.pitch && (n.$1 - d.time).abs() < 0.7,
            )) {
          phantom++;
        }
      }
    }
    for (var i = 0; i < notes.length; i++) {
      if (!used[i]) {
        misses.add('-${notes[i].$2}@${notes[i].$1.toStringAsFixed(2)}');
      }
    }
    if (verbose && misses.isNotEmpty) print('${entry.key}: $misses');
    final split = info['split'] ?? 'tune';
    for (final g in ['all', '${info['condition']}', '${info['kind']}']) {
      groups.putIfAbsent('$split:$g', _Score.new)
        ..tp += tp
        ..fp += ons.length - tp
        ..fn += notes.length - tp
        ..errs.addAll(errs)
        ..delays.addAll(delays)
        ..phantom += phantom
        ..seconds += notes.isEmpty ? samples.length / sr : 0
        ..expectedNotes += mode == 'wrong' ? notes.length : 0;
    }
  }
  // Held-out clips first: thresholds were tuned on the 'tune' split only.
  for (final split in ['test', 'tune']) {
    print('');
    print('$split set${split == 'test' ? ' (held out)' : ''}:');
    print(
      '| Group | Notes | P | R | F1 | Onset error mean / p95 (ms) '
      '| Computed report delay p50 / p95 (ms) |',
    );
    print('|---|---|---|---|---|---|---|');
    for (final g in [
      'all',
      'clean',
      'room',
      'noisy',
      'single',
      'chord',
      'doubled',
      'noise',
      'melody',
      'two-hands',
    ]) {
      final s = groups['$split:$g'];
      if (s != null) print(s.row(g));
    }
  }
}

class _Score {
  int tp = 0, fp = 0, fn = 0, phantom = 0, expectedNotes = 0;
  double seconds = 0; // noise-only audio, for false notes per minute
  final errs = <double>[];
  final delays = <double>[];

  String row(String name) {
    if (tp + fn == 0 && seconds > 0) {
      final perMin = fp / seconds * 60;
      return '| $name | 0 | false notes: $fp in ${seconds.toStringAsFixed(0)} s '
          '= ${perMin.toStringAsFixed(1)}/min | | | | |';
    }
    final p = tp / (tp + fp == 0 ? 1 : tp + fp);
    final r = tp / (tp + fn == 0 ? 1 : tp + fn);
    final f = p + r == 0 ? 0 : 2 * p * r / (p + r);
    final abs = errs.map((e) => e.abs()).toList()..sort();
    final mean = errs.isEmpty ? 0 : errs.reduce((a, b) => a + b) / errs.length;
    final dl = [...delays]..sort();
    String q(List<double> l, double x) => l.isEmpty
        ? '-'
        : l[(l.length * x).floor().clamp(0, l.length - 1)].toStringAsFixed(0);
    return '| $name | ${tp + fn} | ${p.toStringAsFixed(3)} | ${r.toStringAsFixed(3)} '
        '| ${f.toStringAsFixed(3)} | ${mean.toStringAsFixed(1)} / ${q(abs, 0.95)} '
        '| ${q(dl, 0.5)} / ${q(dl, 0.95)} |'
        '${expectedNotes == 0 ? '' : ' phantom $phantom/$expectedNotes |'}';
  }
}

(int, List<double>) _readWav(File f) {
  final b = f.readAsBytesSync();
  final data = ByteData.sublistView(b);
  final sr = data.getUint32(24, Endian.little);
  var off = 12;
  while (off < b.length - 8) {
    final id = String.fromCharCodes(b.sublist(off, off + 4));
    final len = data.getUint32(off + 4, Endian.little);
    if (id == 'data') {
      return (
        sr,
        [
          for (var i = 0; i < len ~/ 2; i++)
            data.getInt16(off + 8 + i * 2, Endian.little) / 32768.0,
        ],
      );
    }
    off += 8 + len;
  }
  throw FormatException('no data chunk in ${f.path}');
}
