import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:easy_piano/content/content_repo.dart';
import 'package:easy_piano/input/midi_input.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:easy_piano/practice/generated/model_store.dart';
import 'package:easy_piano/practice/generated/practice_service.dart';
import 'package:easy_piano/practice/generated/practice_stream.dart';
import 'package:easy_piano/practice/generated/song_feed.dart';
import 'package:easy_piano/practice/generated/stream_practice_page.dart';
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

final _node = PracticeNodeDef(
  course: 'c',
  node: 'n',
  rubricJson: jsonEncode({
    'taught': {
      'pitches': {
        'RH': [60, 62, 64, 65, 67],
        'LH': [48, 50],
      },
      'durations': ['2', '4', '8'],
      'rest_durations': ['2'],
      'rests': true,
      'max_interval': 4,
      'polyphony': {'RH': 1, 'LH': 1},
    },
    'spec': {
      'node': 'n',
      'new_skill': 'x',
      'required': [
        {'rhythm': '8'},
      ],
      'bars': [4, 8],
      'bpm': [70, 90],
      'hands': 'RH',
      'time': '4/4',
    },
  }),
  gen: const {
    'bpm': 80,
    'level': 1,
    'hands': 'RH',
    'time': '4/4',
    'durs': ['2', '4'],
  },
);

Candidate _cand(String rh) => {
  'time': '4/4',
  'key': 'C',
  'bars': [
    for (var i = 0; i < 4; i++) {'RH': rh},
  ],
};

/// Fails any song with an A4 (stands in for the core rubric, which is not
/// loaded in `flutter test`; core/src/rubric.rs tests check_generated).
List<String> _rubric(String song, String node) =>
    song.contains('A4') ? ['RH: pitches not taught: A4'] : [];

class _FakeGenerator implements TuneGenerator {
  _FakeGenerator(this.rounds, {this.supported = true});

  /// Candidates per call, in order.
  final List<List<Candidate>> rounds;
  @override
  final bool supported;
  final specs = <Map<String, dynamic>>[];

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
  }) async {
    specs.add(gen);
    return rounds[(specs.length - 1) % rounds.length];
  }
}

StreamSettings _settings() => StreamSettings(
  node: _node,
  hands: 'RH',
  bpm: 100,
  durations: ['4'],
  style: 'jazz',
);

int _bars(SongFeed feed) =>
    ((jsonDecode(feed.json) as Map)['bars'] as List).length;

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

  group('stream rubric gate', () {
    test('a rubric-failing chunk is never pushed', () async {
      final gen = _FakeGenerator([
        [_cand('A4:1'), _cand('C4:4 D4:4 E4:4 D4:4')],
      ]);
      String? node;
      final s = PracticeStream(
        gen,
        _settings(),
        rubric: (song, n) {
          node = n;
          return _rubric(song, n);
        },
        seed: 1,
      );
      final feed = await s.start();
      expect(feed.json, isNot(contains('A4')));
      expect(s.rejected, 1);
      final song = jsonDecode(feed.json) as Map<String, dynamic>;
      expect(song['source'], 'generated');
      expect(song['generator']['method'], 'melody-model');
      expect(song['bpm'], 100);
      // The learner's choices reach both the model and the rubric.
      final spec = (jsonDecode(node!) as Map)['spec'] as Map;
      expect(spec['required'], isEmpty);
      expect(spec['bpm'], [100, 100]);
      final g = gen.specs.first;
      expect(g['durs'], ['4']);
      expect(g['bars'], 4);
      expect(g['styles'], ['jazz']);
      expect((g['mask'] as Map)['pitches'], {
        'RH': ['C4', 'D4', 'E4', 'F4', 'G4'],
      });
    });

    test(
      'grows on demand, carries the last note, ends after failures',
      () async {
        final gen = _FakeGenerator([
          [_cand('C4:4 D4:4 E4:4 F4:4')],
          [_cand('E4:4 D4:4 C4:4 D4:4')],
          [_cand('A4:1')],
          [_cand('A4:2 A4:2')],
        ]);
        final s = PracticeStream(
          gen,
          _settings(),
          rubric: _rubric,
          maxAttempts: 2,
        );
        final feed = await s.start();
        var pushes = 0;
        var ended = false;
        feed.addListener(() => feed.ended ? ended = true : pushes++);
        await s.grow(); // joins the look-ahead chunk start() began
        expect(_bars(feed), 8);
        expect((gen.specs[1]['mask'] as Map)['start'], {'RH': 'F4'});
        feed.onDemand!(100); // plenty left: nothing to do
        expect(gen.specs, hasLength(2));
        feed.onDemand!(4);
        await s.grow();
        expect(
          ended,
          isTrue,
          reason: 'A4 chunks always fail, so the feed ends',
        );
        expect(pushes, 1);
        expect(_bars(feed), 8);
      },
    );

    test('note values must fill a bar', () {
      expect(fillsBar(['4'], '4/4'), isTrue);
      expect(fillsBar(['2.'], '4/4'), isFalse);
      expect(fillsBar(['4.', '8'], '6/8'), isTrue);
      expect(durUnits('4.'), 12);
      expect(pitchName(61), 'C#4');
      expect(NodeChoices(_node).hands, ['RH', 'LH', 'BOTH']);
    });
  });

  group('stream pages', () {
    Widget wrap(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

    StreamPracticePage page(TuneGenerator gen) => StreamPracticePage(
      settings: _settings(),
      generator: gen,
      midi: createMidiInput(),
      title: 'Lesson',
      stream: PracticeStream(gen, _settings(), rubric: _rubric),
      stageBuilder: (context, stage, feed, onFinished, onExit) =>
          ListenableBuilder(
            listenable: feed,
            builder: (_, _) => Column(
              children: [
                Text('bars ${_bars(feed)}'),
                Text('mode ${stage.type} ${stage.hand}'),
                TextButton(
                  onPressed: () => feed.onDemand!(0),
                  child: const Text('near the end'),
                ),
              ],
            ),
          ),
    );

    testWidgets('streams chunks with a Generated badge', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final gen = _FakeGenerator([
        [_cand('A4:1'), _cand('C4:4 D4:4 E4:4 D4:4')],
      ]);
      await tester.pumpWidget(wrap(page(gen)));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(find.text('Generated'), findsOneWidget);
      expect(find.text('mode wait RH'), findsOneWidget);
      expect(find.textContaining('A4'), findsNothing);
      expect(find.text('bars 8'), findsOneWidget, reason: 'one chunk ahead');
      await tester.tap(find.text('near the end'));
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(find.text('bars 12'), findsOneWidget);
    });

    testWidgets('friendly error when no chunk passes', (tester) async {
      final gen = _FakeGenerator([
        [_cand('A4:1')],
      ]);
      await tester.pumpWidget(wrap(page(gen)));
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(find.textContaining("Couldn't make a tune"), findsOneWidget);
      expect(find.textContaining('bars'), findsNothing);
      expect(find.text('RETRY'), findsOneWidget);
    });

    testWidgets('native platforms say not yet', (tester) async {
      await tester.pumpWidget(wrap(page(_FakeGenerator([], supported: false))));
      await tester.pump();
      expect(find.textContaining('only work in the browser'), findsOneWidget);
      expect(find.text('RETRY'), findsNothing);
    });

    testWidgets('setup offers taught choices and blocks bad note values', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = ContentRepo.fromFiles({
        'courses.json': jsonEncode({
          'courses': [
            {
              'id': 'c',
              'title': 'Course',
              'description': '',
              'journey': 'courses/c/journey.json',
            },
          ],
        }),
        'courses/c/journey.json': jsonEncode({
          'nodes': [
            {'id': 'n', 'kind': 'lesson', 'title': 'Node', 'levels': []},
          ],
        }),
        'practice.json': jsonEncode({
          'version': 1,
          'nodes': [
            {
              'course': 'c',
              'node': 'n',
              'practice': jsonDecode(_node.rubricJson),
              'gen': _node.gen,
            },
          ],
        }),
      });
      await tester.pumpWidget(
        wrap(
          StreamSetupPage(
            repo: repo,
            generator: _FakeGenerator([]),
            midi: createMidiInput(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('1'), findsOneWidget, reason: 'one level chip');
      expect(find.text('Any'), findsOneWidget);
      expect(find.text('Jazz'), findsOneWidget);
      expect(find.text('Both'), findsOneWidget);
      expect(find.text('TEMPO · 80 BPM'), findsOneWidget);
      // Only the half note left: it fills 4/4, so PLAY stays on.
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is NoteGlyph && w.glyph == durGlyph('4'),
        ),
      );
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is NoteGlyph && w.glyph == durGlyph('8'),
        ),
      );
      await tester.pump();
      expect(find.textContaining("can't fill a bar"), findsNothing);
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is NoteGlyph && w.glyph == durGlyph('2'),
        ),
      );
      await tester.pump();
      expect(find.textContaining("can't fill a bar"), findsOneWidget);
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
