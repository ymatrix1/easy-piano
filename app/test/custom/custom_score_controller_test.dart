import 'dart:convert';

import 'package:easy_piano/custom/custom_score.dart';
import 'package:easy_piano/custom/custom_score_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory storage that counts writes.
class _MemoryStorage implements ScoreStorage {
  _MemoryStorage([List<String>? initial]) : entries = [...?initial];

  List<String> entries;
  int writes = 0;

  @override
  Future<List<String>> read() async => entries;

  @override
  Future<void> write(List<String> e) async {
    writes++;
    entries = [...e];
  }
}

String _song(String id, {String title = 'Ode to Joy'}) => jsonEncode({
  'id': id,
  'title': title,
  'composer': 'Anon.',
  'arranger': 'Imported',
  'source': 'custom',
  'source_url': null,
  'license': 'user-provided',
  'composition_license': 'user-provided',
  'bpm': 100,
  'time': '3/4',
  'key': 'G',
  'bars': [
    {'RH': 'G4:4 A4:4 B4:4'},
  ],
  'critical': [],
});

CustomScoreController _controller({
  _MemoryStorage? storage,
  Future<String> Function(String, Uint8List)? importer,
}) => CustomScoreController(
  storage: storage ?? _MemoryStorage(),
  importer: importer ?? (name, data) async => _song('ode'),
  clock: () => DateTime.utc(2026, 10, 25, 12),
);

void main() {
  test('importing adds the score first and saves it', () async {
    final storage = _MemoryStorage();
    final c = _controller(storage: storage);
    await c.load();

    final s = await c.importFile('ode.mid', Uint8List.fromList([1, 2]));

    expect(s.id, 'ode');
    expect(s.bars, 1);
    expect(s.timeSignature, '3/4');
    expect(c.scores.single.title, 'Ode to Joy');
    expect(storage.entries, hasLength(1));
    expect(storage.writes, 1);
  });

  test(
    'a second import with the same id gets a new id and its own song id',
    () async {
      final c = _controller(storage: _MemoryStorage());
      await c.load();
      await c.importFile('ode.mid', Uint8List(0));
      final second = await c.importFile('ode.mid', Uint8List(0));

      expect(second.id, 'ode-2');
      expect((jsonDecode(second.songJson) as Map)['id'], 'ode-2');
      expect(c.scores.map((s) => s.id), ['ode-2', 'ode']);
    },
  );

  test('unsupported extensions are refused before the importer runs', () async {
    var called = false;
    final c = _controller(
      importer: (name, data) async {
        called = true;
        return _song('x');
      },
    );
    await c.load();

    await expectLater(
      c.importFile('score.pdf', Uint8List(0)),
      throwsA(
        isA<ScoreImportException>().having(
          (e) => e.reason,
          'reason',
          'unsupported',
        ),
      ),
    );
    expect(called, isFalse);
    expect(c.scores, isEmpty);
  });

  test('a file the parser rejects is reported and not saved', () async {
    final storage = _MemoryStorage();
    final c = _controller(
      storage: storage,
      importer: (name, data) async =>
          throw PlatformException(code: 'parse', message: 'bad'),
    );
    await c.load();

    await expectLater(
      c.importFile('broken.xml', Uint8List(0)),
      throwsA(
        isA<ScoreImportException>().having((e) => e.reason, 'reason', 'failed'),
      ),
    );
    expect(c.scores, isEmpty);
    expect(storage.writes, 0);
  });

  test('remove deletes one score and saves the rest', () async {
    final storage = _MemoryStorage();
    final c = _controller(storage: storage);
    await c.load();
    await c.importFile('a.mid', Uint8List(0));
    await c.importFile('b.mid', Uint8List(0));

    await c.remove('ode');

    expect(c.scores.map((s) => s.id), ['ode-2']);
    expect(storage.entries, hasLength(1));
  });

  test('load restores saved scores and skips a corrupt entry', () async {
    final good = CustomScore(
      id: 'ode',
      title: 'Ode to Joy',
      composer: 'Anon.',
      fileName: 'ode.mid',
      bars: 1,
      timeSignature: '3/4',
      songJson: _song('ode'),
      importedAt: DateTime.utc(2026),
    );
    final storage = _MemoryStorage([jsonEncode(good.toJson()), '{not json']);
    final c = _controller(storage: storage);

    expect(c.loaded, isFalse);
    await c.load();

    expect(c.loaded, isTrue);
    expect(c.scores.map((s) => s.id), ['ode']);
  });

  test('the prefs storage keeps the library between sessions', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = PrefsScoreStorage();
    expect(await storage.read(), isEmpty);

    await storage.write(['one', 'two']);
    expect(await PrefsScoreStorage().read(), ['one', 'two']);
  });

  test('the controller notifies listeners on import', () async {
    final c = _controller();
    var notified = 0;
    c.addListener(() => notified++);
    await c.load();
    await c.importFile('ode.mid', Uint8List(0));
    expect(notified, 2); // load, then import
  });
}
