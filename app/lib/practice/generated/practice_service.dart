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

/// No chunk passed the rubric within [PracticeStream.maxAttempts].
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
