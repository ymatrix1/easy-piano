import 'dart:convert';

import 'package:easy_piano/custom/custom_score.dart';
import 'package:easy_piano/content/content_repo.dart';
import 'package:flutter_test/flutter_test.dart';

const _songJson =
    '{"id":"ode","title":"Ode to Joy","composer":"L. van Beethoven",'
    '"arranger":"Imported","source":"custom","source_url":null,'
    '"license":"user-provided","composition_license":"user-provided",'
    '"bpm":100,"time":"4/4","key":"C",'
    '"bars":[{"RH":"C4:4 D4:4 E4:4 F4:4"},{"RH":"G4:1"}],"critical":[]}';

CustomScore _score({
  String id = 'ode',
  String title = 'Ode to Joy',
  String composer = 'L. van Beethoven',
}) => CustomScore(
  id: id,
  title: title,
  composer: composer,
  fileName: 'ode.mid',
  bars: 2,
  timeSignature: '4/4',
  songJson: _songJson,
  importedAt: DateTime.utc(2026, 10, 25, 12),
);

void main() {
  test('only the importer extensions are supported', () {
    for (final name in [
      'a.xml',
      'a.musicxml',
      'a.mxl',
      'a.mid',
      'a.MIDI',
      'a.abc',
      'a.ly',
    ]) {
      expect(isSupportedScoreFile(name), isTrue, reason: name);
    }
    for (final name in ['a.pdf', 'a.mp3', 'noext', 'a.']) {
      expect(isSupportedScoreFile(name), isFalse, reason: name);
    }
  });

  test('library entry is read from the content song JSON', () {
    final s = scoreFromSongJson(
      songJson: _songJson,
      fileName: 'ode.mid',
      importedAt: DateTime.utc(2026),
    );
    expect(s.id, 'ode');
    expect(s.title, 'Ode to Joy');
    expect(s.composer, 'L. van Beethoven');
    expect(s.bars, 2);
    expect(s.timeSignature, '4/4');
  });

  test('missing title and composer fall back to the file name and Unknown', () {
    final json = jsonEncode({
      ...jsonDecode(_songJson) as Map<String, dynamic>,
      'title': '  ',
      'composer': '',
    });
    final s = scoreFromSongJson(
      songJson: json,
      fileName: 'My Tune.ly',
      importedAt: DateTime.utc(2026),
    );
    expect(s.title, 'My Tune');
    expect(s.composer, 'Unknown');
  });

  test('json round trip keeps every field', () {
    final s = _score();
    final back = CustomScore.fromJson(
      jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
    );
    expect(back.id, s.id);
    expect(back.title, s.title);
    expect(back.songJson, s.songJson);
    expect(back.importedAt, s.importedAt);
  });

  test('withSongId replaces only the id', () {
    final out =
        jsonDecode(withSongId(_songJson, 'ode-2')) as Map<String, dynamic>;
    expect(out['id'], 'ode-2');
    expect(out['title'], 'Ode to Joy');
  });

  test('uniqueScoreId adds a counter when the id is taken', () {
    expect(uniqueScoreId('ode', {}), 'ode');
    expect(uniqueScoreId('ode', {'ode'}), 'ode-2');
    expect(uniqueScoreId('ode', {'ode', 'ode-2'}), 'ode-3');
  });

  test('search matches title or composer, ignoring case', () {
    final scores = [
      _score(id: 'a', title: 'Ode to Joy', composer: 'Beethoven'),
      _score(id: 'b', title: 'Clair de lune', composer: 'Debussy'),
    ];
    expect(searchScores(scores, '').map((s) => s.id), ['a', 'b']);
    expect(searchScores(scores, 'JOY').map((s) => s.id), ['a']);
    expect(searchScores(scores, ' debussy ').map((s) => s.id), ['b']);
    expect(searchScores(scores, 'bach'), isEmpty);
  });

  test('custom level plays the score on both hands', () {
    final level = customLevelFor(_score());
    expect(level.id, 'custom-ode');
    expect(level.stages, hasLength(1));
    expect(level.stages.single.type, 'play_along');
    expect(level.stages.single.score, 'ode');
    expect(level.stages.single.hand, 'both');
  });

  test('repoWithScore adds the song and keeps the base content', () {
    final base = ContentRepo(
      courses: const [],
      levels: const {},
      songJson: const {'other': '{}'},
      scenes: const {},
      stringsByLocale: const {
        'en': {'k': 'v'},
      },
    );
    final repo = repoWithScore(base, _score());
    expect(repo.songJson['ode'], _songJson);
    expect(repo.songJson['other'], '{}');
    expect(repo.levels['custom-ode']?.title, 'Ode to Joy');
    expect(repo.stringsByLocale['en']?['k'], 'v');
    expect(base.songJson.containsKey('ode'), isFalse);
  });
}
