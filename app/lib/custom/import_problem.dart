/// Largest score file the importer reads. Real scores are far smaller; this stops a
/// wrong file (a video, an archive) from being read into memory.
const maxScoreFileBytes = 2 * 1024 * 1024;

/// Scores kept in the library, and the room they may take together. The web build
/// stores them in `localStorage`, which holds about 5 million characters.
const maxLibraryScores = 100;
const maxLibraryChars = 3 * 1000 * 1000;

/// Why one file did not make it into the library. Each value has a plain-language
/// message and a next step in `import_results_dialog.dart`.
enum ImportProblem {
  unsupportedType,
  empty,
  tooLarge,
  unreadable,
  noNotes,
  unsupportedMusic,
  duplicate,
  libraryFull,
  storageFull,
  unknown,
}

/// Sorts a parser error from `core` `score_import` into an [ImportProblem].
ImportProblem classifyImportError(String message) {
  final m = message.toLowerCase();
  if (m.contains('no notes found') || m.contains('no measures')) {
    return ImportProblem.noNotes;
  }
  if (m.contains('not supported') ||
      m.contains('unsupported musicxml root') ||
      m.contains('out of range') ||
      m.contains('more than two voices') ||
      m.contains('smpte')) {
    return ImportProblem.unsupportedMusic;
  }
  if (m.contains('unclosed') ||
      m.contains('utf-8') ||
      m.contains('mthd') ||
      m.contains('short header') ||
      m.contains('missing k:') ||
      m.contains('data byte') ||
      m.contains('variable-length') ||
      m.contains('zip') ||
      m.contains('xml') ||
      m.contains('midi') ||
      m.contains('abc') ||
      m.contains('lilypond')) {
    return ImportProblem.unreadable;
  }
  return ImportProblem.unknown;
}
