import 'dart:convert';

import '../content/content_repo.dart';

/// A score the player imported, kept on the device (piano-uy13, D40).
///
/// [songJson] is the content song from `import_score` (docs/specs/content-format.md)
/// with `id` set to [id], so it plays through the same practice code as bundled songs.
class CustomScore {
  const CustomScore({
    required this.id,
    required this.title,
    required this.composer,
    required this.fileName,
    required this.bars,
    required this.timeSignature,
    required this.songJson,
    required this.importedAt,
  });

  factory CustomScore.fromJson(Map<String, dynamic> j) => CustomScore(
    id: j['id'] as String,
    title: j['title'] as String,
    composer: j['composer'] as String,
    fileName: j['fileName'] as String,
    bars: j['bars'] as int,
    timeSignature: j['timeSignature'] as String,
    songJson: j['songJson'] as String,
    importedAt: DateTime.parse(j['importedAt'] as String),
  );

  final String id;
  final String title;
  final String composer;
  final String fileName;
  final int bars;
  final String timeSignature;
  final String songJson;
  final DateTime importedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'composer': composer,
    'fileName': fileName,
    'bars': bars,
    'timeSignature': timeSignature,
    'songJson': songJson,
    'importedAt': importedAt.toUtc().toIso8601String(),
  };
}

/// Extensions the importer reads (the same list as `core` `score_import::detect_format`).
const scoreFileExtensions = [
  'xml',
  'musicxml',
  'mxl',
  'mid',
  'midi',
  'abc',
  'ly',
];

bool isSupportedScoreFile(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0) return false;
  return scoreFileExtensions.contains(
    fileName.substring(dot + 1).toLowerCase(),
  );
}

/// Reads the library entry from the content song JSON returned by the importer.
///
/// Title and composer fall back to the file name and "Unknown" when the file has none.
CustomScore scoreFromSongJson({
  required String songJson,
  required String fileName,
  required DateTime importedAt,
}) {
  final song = jsonDecode(songJson) as Map<String, dynamic>;
  final bars = (song['bars'] as List).length;
  final stem = fileName.contains('.')
      ? fileName.substring(0, fileName.lastIndexOf('.'))
      : fileName;
  final title = (song['title'] as String).trim();
  final composer = (song['composer'] as String).trim();
  return CustomScore(
    id: song['id'] as String,
    title: title.isEmpty ? stem : title,
    composer: composer.isEmpty ? 'Unknown' : composer,
    fileName: fileName,
    bars: bars,
    timeSignature: song['time'] as String,
    songJson: songJson,
    importedAt: importedAt,
  );
}

/// Whether two song JSONs are the same music, ignoring the `id` each was given.
bool sameScore(String a, String b) {
  final x = jsonDecode(a) as Map<String, dynamic>..remove('id');
  final y = jsonDecode(b) as Map<String, dynamic>..remove('id');
  return jsonEncode(x) == jsonEncode(y);
}

/// The song JSON with its `id` replaced, so the library can hold two scores with
/// the same id from the importer under different ids.
String withSongId(String songJson, String id) {
  final song = jsonDecode(songJson) as Map<String, dynamic>;
  song['id'] = id;
  return jsonEncode(song);
}

/// [base] when free, else `base-2`, `base-3`, ...
String uniqueScoreId(String base, Set<String> taken) {
  if (!taken.contains(base)) return base;
  for (var n = 2; ; n++) {
    final candidate = '$base-$n';
    if (!taken.contains(candidate)) return candidate;
  }
}

/// Scores whose title or composer contains [query], ignoring case. An empty query
/// returns all scores in their stored order.
List<CustomScore> searchScores(List<CustomScore> scores, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return List.of(scores);
  return [
    for (final s in scores)
      if (s.title.toLowerCase().contains(q) ||
          s.composer.toLowerCase().contains(q))
        s,
  ];
}

/// A level that plays one imported score: a single play-along stage on both hands.
LevelDef customLevelFor(CustomScore score) => LevelDef(
  id: 'custom-${score.id}',
  title: score.title,
  stages: [StageDef(type: 'play_along', score: score.id, hand: 'both')],
  ui: 'both',
);

/// A content repo that also knows the imported score, for [LevelPage].
ContentRepo repoWithScore(ContentRepo base, CustomScore score) => ContentRepo(
  courses: base.courses,
  sections: base.sections,
  levels: {...base.levels, customLevelFor(score).id: customLevelFor(score)},
  songJson: {...base.songJson, score.id: score.songJson},
  scenes: base.scenes,
  stringsByLocale: base.stringsByLocale,
  locale: base.locale,
  practice: base.practice,
  melodyManifest: base.melodyManifest,
);
