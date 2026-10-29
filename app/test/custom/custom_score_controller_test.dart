import 'dart:convert';

import 'package:easy_piano/custom/custom_score.dart';
import 'package:easy_piano/custom/custom_score_controller.dart';
import 'package:easy_piano/custom/import_problem.dart';
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory storage that counts writes.
class _MemoryStorage implements ScoreStorage {
  _MemoryStorage([List<String>? initial]) : entries = [...?initial];

  List<String> entries;
  int writes = 0;
  bool failWrites = false;

  @override
  Future<List<String>> read() async => entries;

  @override
  Future<void> write(List<String> e) async {
    if (failWrites) throw StateError('quota exceeded');
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

class _ThrowingStorage implements ScoreStorage {
  @override
  Future<List<String>> read() async => throw StateError('blocked');

  @override
  Future<void> write(List<String> entries) async {}
}

Matcher _problem(ImportProblem p) =>
    isA<ScoreImportException>().having((e) => e.problem, 'problem', p);

CustomScoreController _controller({
  ScoreStorage? storage,
  Future<String> Function(String, Uint8List)? importer,
}) => CustomScoreController(
  storage: storage ?? _MemoryStorage(),
  importer:
      importer ??
      (name, data) async =>
          _song('ode', title: name == 'ode.mid' ? 'Ode to Joy' : 'Ode $name'),
  clock: () => DateTime.utc(2026, 10, 25, 12),
);

final _bytes = Uint8List.fromList([1, 2, 3]);

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
      var n = 0;
      final c = _controller(
        storage: _MemoryStorage(),
        importer: (name, data) async => _song('ode', title: 'Ode ${n++}'),
      );
      await c.load();
      await c.importFile('ode.mid', _bytes);
      final second = await c.importFile('ode.mid', _bytes);

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
      c.importFile('score.pdf', _bytes),
      throwsA(
        isA<ScoreImportException>().having(
          (e) => e.problem,
          'problem',
          ImportProblem.unsupportedType,
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
      c.importFile('broken.xml', _bytes),
      throwsA(
        isA<ScoreImportException>().having(
          (e) => e.problem,
          'problem',
          ImportProblem.unknown,
        ),
      ),
    );
    expect(c.scores, isEmpty);
    expect(storage.writes, 0);
  });

  test('remove deletes one score and saves the rest', () async {
    final storage = _MemoryStorage();
    final c = _controller(storage: storage);
    await c.load();
    await c.importFile('a.mid', _bytes);
    await c.importFile('b.mid', _bytes);

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
    await c.importFile('ode.mid', _bytes);
    expect(notified, 2); // load, then import
  });

  test('an empty file is refused before the importer runs', () async {
    var called = false;
    final c = _controller(
      importer: (name, data) async {
        called = true;
        return _song('x');
      },
    );
    await c.load();
    await expectLater(
      c.importFile('empty.abc', Uint8List(0)),
      throwsA(_problem(ImportProblem.empty)),
    );
    expect(called, isFalse);
  });

  test('a file over the size limit is refused unread', () async {
    final c = _controller();
    await c.load();
    await expectLater(
      c.importFile('huge.mid', Uint8List(maxScoreFileBytes + 1)),
      throwsA(_problem(ImportProblem.tooLarge)),
    );
    expect(c.scores, isEmpty);
  });

  test('parser errors are sorted into plain problems', () async {
    final c = _controller(
      importer: (name, data) async => throw 'abc: no notes found',
    );
    await c.load();
    await expectLater(
      c.importFile('a.abc', _bytes),
      throwsA(_problem(ImportProblem.noNotes)),
    );
  });

  test(
    'importing the same music twice is a duplicate, not a second row',
    () async {
      final storage = _MemoryStorage();
      final c = _controller(
        storage: storage,
        importer: (name, data) async => _song('twinkle', title: 'Twinkle'),
      );
      await c.load();
      await c.importFile('twinkle.abc', _bytes);
      await expectLater(
        c.importFile('twinkle-copy.abc', _bytes),
        throwsA(_problem(ImportProblem.duplicate)),
      );
      expect(c.scores, hasLength(1));
      expect(storage.writes, 1);
    },
  );

  test(
    'a failed save keeps the library as it was and says storage is full',
    () async {
      final storage = _MemoryStorage()..failWrites = true;
      final c = _controller(storage: storage);
      await c.load();
      var notified = 0;
      c.addListener(() => notified++);

      await expectLater(
        c.importFile('ode.mid', _bytes),
        throwsA(_problem(ImportProblem.storageFull)),
      );

      expect(c.scores, isEmpty);
      expect(notified, 0);
    },
  );

  test('a library past its character budget refuses another score', () async {
    final big = jsonEncode({
      ...(jsonDecode(_song('big')) as Map<String, dynamic>),
      'pad': 'x' * (maxLibraryChars ~/ 2),
    });
    final c = _controller(importer: (name, data) async => big);
    await c.load();
    await expectLater(
      c.importFile('big.mid', _bytes),
      throwsA(_problem(ImportProblem.libraryFull)),
    );
  });

  test('imports started together all land in the library', () async {
    final storage = _MemoryStorage();
    final c = _controller(storage: storage);
    await c.load();
    await Future.wait([
      c.importFile('a.mid', _bytes),
      c.importFile('b.mid', _bytes),
      c.importFile('c.mid', _bytes),
    ]);
    expect(c.scores, hasLength(3));
    expect(storage.entries, hasLength(3));
  });

  test('importFiles reports each file and keeps the good ones', () async {
    final c = _controller();
    await c.load();
    final outcome = await c.importFiles([
      XFile.fromData(_bytes, path: 'a.mid'),
      XFile.fromData(_bytes, path: 'notes.txt'),
      XFile.fromData(Uint8List(0), path: 'empty.abc'),
      XFile.fromData(Uint8List(maxScoreFileBytes + 1), path: 'huge.mid'),
      XFile.fromData(_bytes, path: 'b.mid'),
    ]);
    expect(outcome.imported.map((s) => s.fileName), ['a.mid', 'b.mid']);
    expect(
      [for (final f in outcome.failures) (f.fileName, f.problem)],
      [
        ('notes.txt', ImportProblem.unsupportedType),
        ('empty.abc', ImportProblem.empty),
        ('huge.mid', ImportProblem.tooLarge),
      ],
    );
  });

  test('a blocked storage loads as an empty library', () async {
    final c = _controller(storage: _ThrowingStorage());
    await c.load();
    expect(c.loaded, isTrue);
    expect(c.scores, isEmpty);
  });
}
