import 'dart:async';
import 'dart:convert';

import '../../src/rust/api/practice.dart' as rust;
import 'practice_service.dart';
import 'song_feed.dart';

const _names = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

/// Pitch name as the content tools write it (`C#4`, middle C = `C4`).
String pitchName(int midi) => '${_names[midi % 12]}${midi ~/ 12 - 1}';

/// What the learner picked on the setup screen (docs/specs/practice-mode.md).
class StreamSettings {
  const StreamSettings({
    required this.node,
    required this.hands,
    required this.bpm,
    required this.durations,
    this.mode = 'wait',
    this.style,
    this.accompaniment = true,
  });

  /// The level: a course node; its taught set bounds every note.
  final PracticeNodeDef node;

  /// `RH`, `LH` or `BOTH`.
  final String hands;
  final int bpm;

  /// Note values to use, a subset of the taught ones.
  final List<String> durations;

  /// `wait` or `play_along`.
  final String mode;

  /// Model style token (`folk`, `jazz`, ...); null lets the model choose.
  final String? style;

  /// Add generated BASS / ACC / DRUMS (core `accompany`) to every chunk.
  final bool accompaniment;
}

/// Choices the setup screen offers for a node, from its taught set.
class NodeChoices {
  NodeChoices(PracticeNodeDef node)
    : _taught =
          (jsonDecode(node.rubricJson) as Map<String, dynamic>)['taught']
              as Map<String, dynamic>;

  final Map<String, dynamic> _taught;

  List<int> pitches(String hand) => [
    for (final p
        in (_taught['pitches'] as Map<String, dynamic>?)?[hand] ?? const [])
      (p as num).toInt(),
  ];

  /// Hand options with taught notes: RH, LH and, when both are taught, BOTH.
  List<String> get hands => [
    if (pitches('RH').isNotEmpty) 'RH',
    if (pitches('LH').isNotEmpty) 'LH',
    if (pitches('RH').isNotEmpty && pitches('LH').isNotEmpty) 'BOTH',
  ];

  /// Taught note values the model can write, longest first.
  List<String> get durations => [
    for (final d in modelDurations)
      if ((_taught['durations'] as List).contains(d)) d,
  ];

  List<String> get restDurations => _taught['rests'] == true
      ? [
          for (final d in modelDurations)
            if ((_taught['rest_durations'] as List? ?? const []).contains(d)) d,
        ]
      : const [];

  int poly(String hand) =>
      ((_taught['polyphony'] as Map<String, dynamic>?)?[hand] as num?)
          ?.toInt() ??
      1;

  int get maxLeap => (_taught['max_interval'] as num?)?.toInt() ?? 12;
}

/// Duration labels in model vocabulary order (melody.js `DURATIONS`).
const modelDurations = [
  '1',
  '1.',
  '2',
  '2.',
  '2..',
  '4',
  '4.',
  '4..',
  '8',
  '8.',
  '16',
  '16.',
  '32', //
];

/// Length in 32nd notes (`4.` = 12).
int durUnits(String d) {
  final base = int.parse(d.replaceAll('.', ''));
  final dots = d.length - d.replaceAll('.', '').length;
  var add = 32 ~/ base, out = add;
  for (var i = 0; i < dots; i++) {
    add ~/= 2;
    out += add;
  }
  return out;
}

/// Whether [durs] can fill a bar of [time] exactly.
bool fillsBar(List<String> durs, String time) {
  final parts = time.split('/').map(int.parse).toList();
  final cap = parts[0] * 32 ~/ parts[1];
  final ok = List<bool>.filled(cap + 1, false)..[0] = true;
  for (var r = 1; r <= cap; r++) {
    ok[r] = durs.any((d) => durUnits(d) <= r && ok[r - durUnits(d)]);
  }
  return ok[cap];
}

/// Writes backing parts into bars: (song JSON, style, hands played) → bars JSON.
typedef Accompany = String Function(
  String songJson,
  String style,
  List<String> hands,
);

/// Default: the Rust core (`accompany::accompany`).
String coreAccompany(String songJson, String style, List<String> hands) =>
    rust.accompanyBars(songJson: songJson, style: style, hands: hands);

/// Endless practice: generates the tune in chunks while the learner plays,
/// each chunk rubric-checked as part of the whole song so far before it is
/// pushed to the [feed] (D28). Nothing is saved.
class PracticeStream {
  PracticeStream(
    this.generator,
    this.settings, {
    this.rubric = coreRubric,
    this.accompany = coreAccompany,
    this.chunkBars = 4,
    this.maxAttempts = 4,
    this.candidates = 4,
    this.aheadBeats = 24,
    this.roundTimeout = const Duration(seconds: 60),
    int? seed,
  }) : _seed = seed ?? DateTime.now().millisecondsSinceEpoch & 0x7fffffff;

  final TuneGenerator generator;
  final StreamSettings settings;
  final RubricCheck rubric;
  final Accompany accompany;
  final int chunkBars;
  final int maxAttempts;
  final int candidates;

  /// Keep at least this many beats generated past the playhead.
  final double aheadBeats;
  final Duration roundTimeout;
  int _seed;

  final _bars = <Map<String, dynamic>>[];
  SongFeed? _feed;
  Future<bool>? _growing;
  bool _failed = false;
  String _time = '4/4';

  /// Chunks that passed, and candidates the rubric refused (for the note).
  int chunks = 0;
  int rejected = 0;

  /// Time to generate each chunk (ms), for measurements.
  final chunkMs = <int>[];

  /// Set once [start] produced the first chunk; the stage reads it.
  SongFeed get feed => _feed!;

  /// The rubric node with the learner's choices: hands, tempo, any length,
  /// no required pattern per chunk (the taught set still bounds every note).
  late final String _rubricNode = () {
    final j = jsonDecode(settings.node.rubricJson) as Map<String, dynamic>;
    final spec = Map<String, dynamic>.from(j['spec'] as Map);
    spec['required'] = <Object>[];
    spec['bars'] = [1, 100000];
    spec['bpm'] = [settings.bpm, settings.bpm];
    spec['hands'] = settings.hands == 'BOTH' ? 'both' : settings.hands;
    return jsonEncode({'taught': j['taught'], 'spec': spec});
  }();

  List<String> get _hands =>
      settings.hands == 'BOTH' ? const ['RH', 'LH'] : [settings.hands];

  Map<String, dynamic> _genSpec() {
    final c = NodeChoices(settings.node);
    final base = settings.node.gen!;
    _time = base['time'] as String;
    final all = [for (final h in _hands) ...c.pitches(h)]..sort();
    return {
      ...base,
      'bars': chunkBars,
      'bpm': settings.bpm,
      'hands': settings.hands,
      'durs': settings.durations,
      'patterns': <Object>[],
      'styles': [?settings.style],
      'range_lo': pitchName(all.first),
      'range_hi': pitchName(all.last),
      'mask': {
        'pitches': {
          for (final h in _hands)
            h: [for (final p in c.pitches(h)) pitchName(p)],
        },
        'max_leap': c.maxLeap,
        'poly': {for (final h in _hands) h: c.poly(h).clamp(1, 4)},
        'rest_durs': c.restDurations,
        'start': _lastNotes(),
      },
    };
  }

  static final _pitchRe = RegExp(r'[A-G][#b]?\d');

  /// Last sounding note per hand (lowest of a chord), for the leap mask.
  Map<String, String> _lastNotes() {
    final out = <String, String>{};
    for (final h in _hands) {
      for (final bar in _bars.reversed) {
        final toks = (bar[h] as String? ?? '')
            .split(' ')
            .where((t) => t.isNotEmpty && !t.startsWith('r:') && t != '{tie}');
        if (toks.isEmpty) continue;
        out[h] = _pitchRe.firstMatch(toks.last.split(':').first)!.group(0)!;
        break;
      }
    }
    return out;
  }

  String _song(List<Map<String, dynamic>> bars) => jsonEncode({
    'id': 'practice-stream-${settings.node.course}-${settings.node.node}',
    'title': 'Generated practice',
    'composer': 'Easy Piano melody model',
    'arranger': 'Easy Piano melody model',
    'source': 'generated',
    'source_url': null,
    'license': 'CC0-1.0',
    'composition_license': 'CC0-1.0',
    'generator': {
      'method': 'melody-model',
      'tool': 'app practice stream',
      'model': 'melody-model-v1',
    },
    'spec_node': settings.node.key,
    'bpm': settings.bpm,
    'time': _time,
    'key': 'C',
    'bars': bars,
  });

  /// Generates the first chunk and creates the feed. Throws
  /// [PracticeUnavailable] when no chunk passes.
  Future<SongFeed> start() async {
    if (!await _grow()) {
      throw PracticeUnavailable('no chunk passed the rubric');
    }
    final feed = _feed = SongFeed(_song(_bars));
    feed.onDemand = (left) {
      if (left < aheadBeats) unawaited(grow());
    };
    unawaited(grow()); // keep one chunk ahead from the start
    return feed;
  }

  /// One more chunk, unless one is already being made. Ends the feed after
  /// a chunk fails every attempt, so the stage can finish.
  Future<bool> grow() {
    if (_failed) return Future.value(false);
    return _growing ??= _grow().then((ok) {
      _growing = null;
      final feed = _feed;
      if (feed != null) ok ? feed.push(_song(_bars)) : feed.end();
      return ok;
    });
  }

  /// The chunk with backing parts, or as it is when accompaniment is off or
  /// fails (backing is never graded, so the melody alone is still fine).
  List<Map<String, dynamic>> _withBacking(List<Map<String, dynamic>> chunk) {
    if (!settings.accompaniment) return chunk;
    try {
      final bars = jsonDecode(
        accompany(_song(chunk), settings.style ?? '', _hands),
      ) as List;
      return [for (final b in bars) Map<String, dynamic>.from(b as Map)];
    } catch (_) {
      return chunk;
    }
  }

  Future<bool> _grow() async {
    final sw = Stopwatch()..start();
    final gen = _genSpec();
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final List<Candidate> cands;
      try {
        cands = await generator
            .generate(gen, n: candidates, seed: _seed++)
            .timeout(roundTimeout);
      } on TimeoutException {
        continue;
      }
      for (final c in cands) {
        if (c['time'] != _time) continue;
        final next = [
          ..._bars,
          for (final b in c['bars'] as List)
            Map<String, dynamic>.from(b as Map),
        ];
        if (rubric(_song(next), _rubricNode).isEmpty) {
          _bars.addAll(_withBacking(next.sublist(_bars.length)));
          chunks++;
          chunkMs.add(sw.elapsedMilliseconds);
          return true;
        }
        rejected++;
      }
    }
    _failed = true;
    return false;
  }
}
