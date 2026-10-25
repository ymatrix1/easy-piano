import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'custom_score.dart';

/// Turns a score file into content song JSON: the bridge's `import_score`.
typedef ScoreImporter = Future<String> Function(
  String fileName,
  Uint8List data,
);

/// Reads and writes the library as a list of JSON strings.
abstract class ScoreStorage {
  Future<List<String>> read();
  Future<void> write(List<String> entries);
}

/// Library in `shared_preferences`: works on every platform the app runs on.
class PrefsScoreStorage implements ScoreStorage {
  static const _key = 'custom_scores';

  @override
  Future<List<String>> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  @override
  Future<void> write(List<String> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, entries);
  }
}

class ScoreImportException implements Exception {
  const ScoreImportException(this.reason);

  /// `unsupported` for an unknown extension, `failed` when the parser rejects the file.
  final String reason;

  @override
  String toString() => 'ScoreImportException($reason)';
}

/// The player's imported scores, newest first.
class CustomScoreController extends ChangeNotifier {
  CustomScoreController({
    required this.storage,
    required this.importer,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ScoreStorage storage;
  final ScoreImporter importer;
  final DateTime Function() _clock;

  List<CustomScore> _scores = const [];
  bool _loaded = false;

  List<CustomScore> get scores => _scores;
  bool get loaded => _loaded;

  /// Reads the saved library. A corrupt entry is skipped instead of hiding the rest.
  Future<void> load() async {
    final scores = <CustomScore>[];
    for (final raw in await storage.read()) {
      try {
        scores.add(
          CustomScore.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {
        // Skip an entry this version cannot read.
      }
    }
    _scores = scores;
    _loaded = true;
    notifyListeners();
  }

  /// Imports [data] named [fileName] and adds it to the library.
  ///
  /// Throws [ScoreImportException] when the file type is not supported or the
  /// parser rejects it.
  Future<CustomScore> importFile(String fileName, Uint8List data) async {
    if (!isSupportedScoreFile(fileName)) {
      throw const ScoreImportException('unsupported');
    }
    final String json;
    try {
      json = await importer(fileName, data);
    } catch (_) {
      throw const ScoreImportException('failed');
    }
    final parsed = scoreFromSongJson(
      songJson: json,
      fileName: fileName,
      importedAt: _clock(),
    );
    final id = uniqueScoreId(parsed.id, {for (final s in _scores) s.id});
    final score = CustomScore(
      id: id,
      title: parsed.title,
      composer: parsed.composer,
      fileName: parsed.fileName,
      bars: parsed.bars,
      timeSignature: parsed.timeSignature,
      songJson: withSongId(json, id),
      importedAt: parsed.importedAt,
    );
    _scores = [score, ..._scores];
    await _save();
    notifyListeners();
    return score;
  }

  Future<void> remove(String id) async {
    _scores = [
      for (final s in _scores)
        if (s.id != id) s,
    ];
    await _save();
    notifyListeners();
  }

  Future<void> _save() =>
      storage.write([for (final s in _scores) jsonEncode(s.toJson())]);
}
