import 'package:easy_piano/custom/import_problem.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Messages as `core` `score_import` writes them.
  const cases = {
    'abc: no notes found': ImportProblem.noNotes,
    'lilypond: no notes found': ImportProblem.noNotes,
    'musicxml: no measures': ImportProblem.noNotes,
    'meter changes inside the piece are not supported':
        ImportProblem.unsupportedMusic,
    'unsupported MusicXML root `score-timewise` (only score-partwise)':
        ImportProblem.unsupportedMusic,
    'key signature 9 out of range': ImportProblem.unsupportedMusic,
    'more than two voices in one hand at beat 3.00':
        ImportProblem.unsupportedMusic,
    'midi: SMPTE time division is not supported':
        ImportProblem.unsupportedMusic,
    'xml: unclosed element': ImportProblem.unreadable,
    'midi: missing MThd header': ImportProblem.unreadable,
    'midi: short header': ImportProblem.unreadable,
    'abc: missing K: field': ImportProblem.unreadable,
    'abc utf-8: invalid utf-8 sequence': ImportProblem.unreadable,
    'something else entirely': ImportProblem.unknown,
  };

  for (final e in cases.entries) {
    test('"${e.key}" is ${e.value.name}', () {
      expect(classifyImportError(e.key), e.value);
    });
  }

  test('the library limits keep inside the browser quota', () {
    // localStorage holds about 5 million characters; leave room for settings.
    expect(maxLibraryChars, lessThan(5 * 1000 * 1000));
    expect(maxScoreFileBytes, lessThanOrEqualTo(maxLibraryChars));
  });
}
