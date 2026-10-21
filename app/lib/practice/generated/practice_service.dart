import 'dart:async';
import 'dart:convert';

import '../../src/rust/api/practice.dart' as rust;

/// One node of `assets/content/practice.json` (`content practice-pack`).
class PracticeNodeDef {
  const PracticeNodeDef({
    required this.course,
    required this.node,
    required this.rubricJson,
    this.gen,
    this.unavailable,
  });

  factory PracticeNodeDef.fromJson(Map<String, dynamic> j) => PracticeNodeDef(
    course: j['course'] as String,
    node: j['node'] as String,
    rubricJson: jsonEncode(j['practice']),
    gen: j['gen'] as Map<String, dynamic>?,
    unavailable: j['unavailable'] as String?,
  );

  final String course;
  final String node;

  /// `{taught, spec}` for the core's `check_generated`.
  final String rubricJson;

  /// Generation spec and masks for the melody model; null when [unavailable].
  final Map<String, dynamic>? gen;
  final String? unavailable;

  String get key => '$course/$node';
  String get hands => gen?['hands'] as String? ?? 'RH';

  static Map<String, PracticeNodeDef> parsePack(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    final out = <String, PracticeNodeDef>{};
    for (final n in j['nodes'] as List) {
      final d = PracticeNodeDef.fromJson(n as Map<String, dynamic>);
      out[d.key] = d;
    }
    return out;
  }
}

/// A decoded model candidate: `{time, key, bars}` (melody.js `decode`).
typedef Candidate = Map<String, dynamic>;

/// The melody model behind practice mode. Web runs onnxruntime-web
/// (tune_generator_web.dart); other platforms say "not yet".
abstract class TuneGenerator {
  bool get supported;

  /// Downloads (or loads from cache) and verifies the model, then starts the
  /// runtime. [onProgress] gets 0..1 of the download.
  Future<void> prepare({void Function(double fraction)? onProgress});

  /// [n] candidates for [gen], best first (finished ones only).
  Future<List<Candidate>> generate(
    Map<String, dynamic> gen, {
    required int n,
    required int seed,
    double temperature = 0.9,
  });
}

/// A tune that passed the rubric and may be shown.
class GeneratedTune {
  const GeneratedTune({
    required this.songJson,
    required this.seed,
    required this.attempts,
    required this.rejected,
    required this.elapsed,
  });

  final String songJson;
  final int seed;

  /// Generation rounds used (1 = the first round had a passing tune).
  final int attempts;

  /// Candidates the rubric refused before this one.
  final int rejected;
  final Duration elapsed;
}

/// No tune passed the rubric within [PracticeService.maxAttempts].
class PracticeUnavailable implements Exception {
  PracticeUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'PracticeUnavailable: $reason';
}

typedef RubricCheck = List<String> Function(String songJson, String nodeJson);

/// Default gate: the Rust core (`rubric::check_generated`).
List<String> coreRubric(String songJson, String nodeJson) =>
    rust.checkGenerated(songJson: songJson, nodeJson: nodeJson);

/// Generates practice tunes for a node and shows only ones that pass the
/// rubric for that node's taught set (D28). Nothing is saved.
class PracticeService {
  PracticeService(
    this.generator, {
    this.rubric = coreRubric,
    this.maxAttempts = 4,
    this.candidatesPerAttempt = 4,
    this.roundTimeout = const Duration(seconds: 60),
    int? seed,
  }) : _seed = seed ?? DateTime.now().millisecondsSinceEpoch & 0x7fffffff;

  final TuneGenerator generator;
  final RubricCheck rubric;
  final int maxAttempts;
  final int candidatesPerAttempt;

  /// A round that takes longer counts as failed (slow device, stuck runtime).
  final Duration roundTimeout;
  int _seed;

  /// Song JSON for a candidate: marked generated (D17 fields), never written
  /// to content, outside course levels, stars and song slots.
  static String songJson(Candidate c, PracticeNodeDef node, int seed, int i) =>
      jsonEncode({
        'id': 'practice-${node.course}-${node.node}-$seed-$i',
        'title': 'Generated practice',
        'composer': 'Easy Piano melody model',
        'arranger': 'Easy Piano melody model',
        'source': 'generated',
        'source_url': null,
        'license': 'CC0-1.0',
        'composition_license': 'CC0-1.0',
        'generator': {
          'method': 'melody-model',
          'tool': 'app practice mode',
          'model': 'melody-model-v1',
          'seed': seed,
        },
        'spec_node': node.key,
        'bpm': node.gen!['bpm'],
        'time': c['time'],
        'key': c['key'],
        'bars': c['bars'],
      });

  Future<GeneratedTune> next(PracticeNodeDef node) async {
    final gen = node.gen;
    if (gen == null) {
      throw PracticeUnavailable(node.unavailable ?? 'no generation spec');
    }
    final sw = Stopwatch()..start();
    var rejected = 0;
    String? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final seed = _seed++;
      final List<Candidate> cands;
      try {
        cands = await generator
            .generate(gen, n: candidatesPerAttempt, seed: seed)
            .timeout(roundTimeout);
      } on TimeoutException {
        lastError = 'round timed out';
        continue;
      }
      for (final (i, c) in cands.indexed) {
        final song = songJson(c, node, seed, i);
        final errors = rubric(song, node.rubricJson);
        if (errors.isEmpty) {
          return GeneratedTune(
            songJson: song,
            seed: seed,
            attempts: attempt,
            rejected: rejected,
            elapsed: sw.elapsed,
          );
        }
        rejected++;
        lastError = errors.first;
      }
    }
    throw PracticeUnavailable(
      'no tune passed the rubric in $maxAttempts tries'
      '${lastError == null ? '' : ' (last: $lastError)'}',
    );
  }
}
