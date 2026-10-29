import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'custom_score.dart';
import 'import_problem.dart';

/// Turns a score file into content song JSON: the bridge's `import_score`, followed
/// by the playability check, so a score that cannot be practised never reaches the
/// library.
typedef ScoreImporter = Future<String> Function(
  String fileName,
  Uint8List data,
);

/// Reads and writes the library as a list of JSON strings.
abstract class ScoreStorage {
  Future<List<String>> read();

  /// Throws when the entries could not be saved (storage full, blocked).
  Future<void> write(List<String> entries);
}

/// Library in `shared_preferences`: works on every platform the app runs on.
///
/// The progress store (D8) does not exist in the app yet; when it does, the library
/// moves there behind this same interface.
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
    if (!await prefs.setStringList(_key, entries)) {
      throw StateError('shared_preferences refused the write');
    }
  }
}

class ScoreImportException implements Exception {
  const ScoreImportException(this.problem, [this.detail]);

  final ImportProblem problem;

  /// The parser's own message, for logs and bug reports; never shown as the main text.
  final String? detail;

  @override
  String toString() => 'ScoreImportException($problem, $detail)';
}

/// One file that was not imported.
class ImportFailure {
  const ImportFailure(this.fileName, this.problem);

  final String fileName;
  final ImportProblem problem;
}

/// What a multi-file import did.
class ImportOutcome {
  const ImportOutcome({required this.imported, required this.failures});

  final List<CustomScore> imported;
  final List<ImportFailure> failures;
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

  /// Imports and deletes run one after another, so two drops at once cannot lose a score.
  Future<void> _queue = Future.value();

  List<CustomScore> get scores => _scores;
  bool get loaded => _loaded;

  /// Reads the saved library. A corrupt entry is skipped instead of hiding the rest.
  Future<void> load() async {
    final scores = <CustomScore>[];
    try {
      for (final raw in await storage.read()) {
        try {
          scores.add(
            CustomScore.fromJson(jsonDecode(raw) as Map<String, dynamic>),
          );
        } catch (_) {
          // Skip an entry this version cannot read.
        }
      }
    } catch (_) {
      // Storage blocked (private window): start with an empty library.
    }
    _scores = scores;
    _loaded = true;
    notifyListeners();
  }

  /// Imports each of [files] in turn; one bad file does not stop the others.
  Future<ImportOutcome> importFiles(List<XFile> files) async {
    final imported = <CustomScore>[];
    final failures = <ImportFailure>[];
    for (final file in files) {
      try {
        if (!isSupportedScoreFile(file.name)) {
          throw const ScoreImportException(ImportProblem.unsupportedType);
        }
        final size = await file.length();
        if (size == 0) throw const ScoreImportException(ImportProblem.empty);
        if (size > maxScoreFileBytes) {
          throw const ScoreImportException(ImportProblem.tooLarge);
        }
        imported.add(await importFile(file.name, await file.readAsBytes()));
      } on ScoreImportException catch (e) {
        failures.add(ImportFailure(file.name, e.problem));
      } catch (_) {
        failures.add(ImportFailure(file.name, ImportProblem.unreadable));
      }
    }
    return ImportOutcome(imported: imported, failures: failures);
  }

  /// Imports [data] named [fileName] and adds it to the library.
  ///
  /// Throws [ScoreImportException] with the reason when it cannot.
  Future<CustomScore> importFile(String fileName, Uint8List data) {
    final result = _queue.then((_) => _import(fileName, data));
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<CustomScore> _import(String fileName, Uint8List data) async {
    if (!isSupportedScoreFile(fileName)) {
      throw const ScoreImportException(ImportProblem.unsupportedType);
    }
    if (data.isEmpty) throw const ScoreImportException(ImportProblem.empty);
    if (data.length > maxScoreFileBytes) {
      throw const ScoreImportException(ImportProblem.tooLarge);
    }
    if (_scores.length >= maxLibraryScores) {
      throw const ScoreImportException(ImportProblem.libraryFull);
    }
    final String json;
    try {
      json = await importer(fileName, data);
    } catch (e) {
      throw ScoreImportException(classifyImportError('$e'), '$e');
    }
    final CustomScore parsed;
    try {
      parsed = scoreFromSongJson(
        songJson: json,
        fileName: fileName,
        importedAt: _clock(),
      );
    } catch (e) {
      throw ScoreImportException(ImportProblem.unknown, '$e');
    }
    if (_scores.any((s) => sameScore(s.songJson, json))) {
      throw const ScoreImportException(ImportProblem.duplicate);
    }
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
    final next = [score, ..._scores];
    if (_size(next) > maxLibraryChars) {
      throw const ScoreImportException(ImportProblem.libraryFull);
    }
    await _save(next);
    _scores = next;
    notifyListeners();
    return score;
  }

  Future<void> remove(String id) {
    final done = _queue.then((_) async {
      final next = [
        for (final s in _scores)
          if (s.id != id) s,
      ];
      await _save(next);
      _scores = next;
      notifyListeners();
    });
    _queue = done.then<void>((_) {}, onError: (_) {});
    return done;
  }

  /// Saves [next]; a failed write leaves the library as it was.
  Future<void> _save(List<CustomScore> next) async {
    try {
      await storage.write([for (final s in next) jsonEncode(s.toJson())]);
    } catch (e) {
      throw ScoreImportException(ImportProblem.storageFull, '$e');
    }
  }

  static int _size(List<CustomScore> scores) =>
      scores.fold(0, (n, s) => n + s.songJson.length * 2);
}
