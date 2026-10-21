import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:easy_piano/content/content_repo.dart';
import 'package:easy_piano/input/midi_input.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:easy_piano/practice/generated/generated_practice_page.dart';
import 'package:easy_piano/practice/generated/model_store.dart';
import 'package:easy_piano/practice/generated/practice_service.dart';
import 'package:easy_piano/src/rust/api/practice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _sha(List<int> b) => crypto.sha256.convert(b).toString();

/// In-memory server and cache; [serve] maps URL → bytes.
class _FakeIo implements ModelIo {
  _FakeIo(this.serve);

  final Map<String, Uint8List> serve;
  final cache = <String, Uint8List>{};
  final fetched = <String>[];

  @override
  Future<Uint8List> fetch(String url, void Function(int) onBytes) async {
    fetched.add(url);
    final b = serve[url];
    if (b == null) throw StateError('404 $url');
    onBytes(b.length ~/ 2);
    onBytes(b.length);
    return b;
  }

  @override
  Future<String> sha256(Uint8List bytes) async => _sha(bytes);

  @override
  Future<Uint8List?> cacheGet(String key) async => cache[key];

  @override
  Future<void> cachePut(String key, Uint8List bytes) async =>
      cache[key] = bytes;

  @override
  Future<void> cacheDelete(String key) async => cache.remove(key);
}

final _files = {
  for (final n in ModelManifest.runtimeFiles)
    n: Uint8List.fromList(utf8.encode('bytes of $n')),
};

ModelManifest _manifest() => ModelManifest.fromJson(
  jsonEncode({
    'tag': 'melody-model-v1',
    'url': 'https://example.test/rel/{file}',
    'files': {
      for (final e in _files.entries)
        e.key: {'bytes': e.value.length, 'sha256': _sha(e.value)},
    },
    'training': {
      'model': {'layers': 6, 'd': 384, 'heads': 6},
    },
  }),
);

Map<String, Uint8List> _served(String base) => {
  for (final e in _files.entries) '$base${e.key}': e.value,
};

const _node = PracticeNodeDef(
  course: 'c',
  node: 'n',
  rubricJson: '{}',
  gen: {'bpm': 80, 'hands': 'RH'},
);

Candidate _cand(String rh) => {
  'time': '4/4',
  'key': 'C',
  'bars': [
    {'RH': rh},
  ],
};

/// Fails any tune with an A4 (stands in for the core rubric, which is not
/// loaded in `flutter test`; core/src/rubric.rs tests check_generated).
List<String> _rubric(String song, String node) =>
    song.contains('A4') ? ['RH: pitches not taught: A4'] : [];

class _FakeGenerator implements TuneGenerator {
  _FakeGenerator(this.rounds, {this.supported = true});

  /// Candidates per call, in order.
  final List<List<Candidate>> rounds;
  @override
  final bool supported;
  int calls = 0;

  @override
  Future<void> prepare({void Function(double fraction)? onProgress}) async {
    onProgress?.call(0.5);
    onProgress?.call(1);
  }

  @override
  Future<List<Candidate>> generate(
    Map<String, dynamic> gen, {
    required int n,
    required int seed,
    double temperature = 0.9,
  }) async => rounds[calls++ % rounds.length];
}

void main() {
  group('model download sha256 check', () {
    test('verified download is cached and reused without a fetch', () async {
      final io = _FakeIo(_served('https://example.test/rel/'));
      final store = ModelStore(_manifest(), io);
      final seen = <double>[];
      final got = await store.load(onProgress: seen.add);
      expect(got['vocab.json'], _files['vocab.json']);
      expect(seen.last, 1.0);
      expect(io.cache, hasLength(3));
      io.fetched.clear();
      await store.load();
      expect(io.fetched, isEmpty, reason: 'second load comes from the cache');
    });

    test('a tampered download is refused and never cached', () async {
      final served = _served('model/');
      served['model/heads.int8.onnx'] = Uint8List.fromList([1, 2, 3]);
      final io = _FakeIo(served);
      await expectLater(
        ModelStore(_manifest(), io, baseUrl: 'model/').load(),
        throwsA(isA<ModelIntegrityError>()),
      );
      expect(io.cache.keys.where((k) => k.contains('heads')), isEmpty);
    });

    test('a corrupted cache entry is dropped and fetched again', () async {
      final io = _FakeIo(_served('model/'));
      final m = _manifest();
      final key = ModelStore.cacheKey(m.files['decoder.int8.onnx']!);
      io.cache[key] = Uint8List.fromList([9]);
      await ModelStore(m, io, baseUrl: 'model/').load();
      expect(io.fetched, contains('model/decoder.int8.onnx'));
      expect(io.cache[key], _files['decoder.int8.onnx']);
    });

    test('URL template and the repo manifest', () {
      final m = ModelManifest.fromJson(
        File('../tools/melody-model/releases/melody-model-v1.json')
            .readAsStringSync(),
      );
      expect(m.files['decoder.int8.onnx']!.sha256, hasLength(64));
      expect(m.config, {'layers': 6, 'heads': 6, 'd': 384});
      expect(m.urlFor('vocab.json'), endsWith('/melody-model-v1/vocab.json'));
      expect(
        m.urlFor('vocab.json', base: 'melody/model'),
        'melody/model/vocab.json',
      );
      expect(m.urlFor('a', base: 'https://x/{file}?v=1'), 'https://x/a?v=1');
    });
  });

  group('rubric gate', () {
    test('a rubric-failing tune is never returned', () async {
      final gen = _FakeGenerator([
        [_cand('A4:1'), _cand('C4:1')],
      ]);
      final t = await PracticeService(
        gen,
        rubric: _rubric,
        seed: 7,
      ).next(_node);
      expect(t.songJson, isNot(contains('A4')));
      expect(t.rejected, 1);
      final song = jsonDecode(t.songJson) as Map<String, dynamic>;
      expect(song['source'], 'generated');
      expect(song['generator']['method'], 'melody-model');
    });

    test('gives up after maxAttempts when nothing passes', () async {
      final gen = _FakeGenerator([
        [_cand('A4:1'), _cand('A4:2 A4:2')],
      ]);
      await expectLater(
        PracticeService(gen, rubric: _rubric, maxAttempts: 3).next(_node),
        throwsA(isA<PracticeUnavailable>()),
      );
      expect(gen.calls, 3);
    });

    test('the bundled practice pack parses', () {
      final pack = PracticeNodeDef.parsePack(
        jsonEncode({
          'version': 1,
          'nodes': [
            {
              'course': 'c',
              'node': 'n',
              'practice': {'taught': {}, 'spec': {}},
              'unavailable': 'no RH pitches taught yet',
            },
          ],
        }),
      );
      expect(pack['c/n']!.gen, isNull);
    });
  });

  group('practice page', () {
    Widget app(TuneGenerator gen) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GeneratedPracticePage(
        node: _node,
        title: 'Lesson',
        service: PracticeService(gen, rubric: _rubric),
        midi: createMidiInput(),
        stageBuilder: (context, stage, song, onFinished, onExit) => Column(
          children: [
            Text('song ${(jsonDecode(song) as Map)['bars'][0]['RH']}'),
            Text('mode ${stage.type}'),
            TextButton(
              onPressed: () => onFinished(
                ResultView(
                  passed: true,
                  stars: 3,
                  hitRatio: 1,
                  wrong: 0,
                  sections: Float64List(0),
                  threshold: 0.7,
                  suggestPractice: false,
                  notesHit: 3,
                  notesTotal: 4,
                  timing: 1,
                  assists: 0,
                  score: 1,
                  starsExact: 3,
                ),
              ),
              child: const Text('finish'),
            ),
          ],
        ),
      ),
    );

    testWidgets('generates, labels, plays and offers another one', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final gen = _FakeGenerator([
        [_cand('A4:1'), _cand('C4:1')],
        [_cand('E4:1')],
      ]);
      await tester.pumpWidget(app(gen));
      await tester.pump();
      await tester.pump();
      expect(find.text('Generated'), findsOneWidget);
      expect(
        find.text('song C4:1'),
        findsOneWidget,
        reason: 'A4 tune failed the rubric',
      );
      expect(find.text('song A4:1'), findsNothing);
      expect(find.text('mode wait'), findsOneWidget);

      await tester.tap(find.text('finish'));
      await tester.pump();
      expect(find.text('3 of 4 notes'), findsOneWidget);
      expect(find.textContaining('no stars'), findsWidgets);

      await tester.tap(find.text('Play along'));
      await tester.pump();
      await tester.tap(find.text('ANOTHER ONE'));
      await tester.pump();
      await tester.pump();
      expect(find.text('song E4:1'), findsOneWidget);
      expect(find.text('mode play_along'), findsOneWidget);
      expect(find.text('Generated'), findsOneWidget);
    });

    testWidgets('friendly error when no tune passes', (tester) async {
      final gen = _FakeGenerator([
        [_cand('A4:1')],
      ]);
      await tester.pumpWidget(app(gen));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining("Couldn't make a tune"), findsOneWidget);
      expect(find.textContaining('song'), findsNothing);
      expect(find.text('RETRY'), findsOneWidget);
    });

    testWidgets('native platforms say not yet', (tester) async {
      await tester.pumpWidget(app(_FakeGenerator([], supported: false)));
      await tester.pump();
      expect(find.textContaining('only work in the browser'), findsOneWidget);
      expect(find.text('RETRY'), findsNothing);
    });
  });

  test('content repo picks up the practice pack and manifest', () {
    final files = {
      'courses.json': '{"courses": []}',
      'practice.json': '{"version":1,"nodes":[]}',
      'melody-model-v1.json': '{}',
    };
    final repo = ContentRepo.fromFiles(files);
    expect(repo.practice, isEmpty);
    expect(repo.melodyManifest, '{}');
  });
}
