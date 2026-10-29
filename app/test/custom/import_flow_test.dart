import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_piano/custom/custom_score.dart';
import 'package:easy_piano/custom/custom_score_controller.dart';
import 'package:easy_piano/custom/import_flow.dart';
import 'package:easy_piano/custom/import_problem.dart';
import 'package:easy_piano/custom/import_results_dialog.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:easy_piano/ui/game/game_widgets.dart';
import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStorage implements ScoreStorage {
  List<String> entries = [];

  @override
  Future<List<String>> read() async => entries;

  @override
  Future<void> write(List<String> e) async => entries = [...e];
}

String _song(String id, String title) => jsonEncode({
  'id': id,
  'title': title,
  'composer': 'Anon.',
  'bpm': 100,
  'time': '4/4',
  'key': 'C',
  'bars': [
    {'RH': 'C4:4 D4:4 E4:4 F4:4'},
  ],
});

/// The importer fails for names containing `bad` and succeeds otherwise.
CustomScoreController _controller() => CustomScoreController(
  storage: _MemoryStorage(),
  importer: (name, data) async {
    if (name.contains('bad')) throw 'abc: no notes found';
    return _song(name.split('.').first, 'Song ${name.split('.').first}');
  },
);

XFile _file(String name, {int size = 3}) =>
    XFile.fromData(Uint8List(size)..fillRange(0, size, 1), path: name);

Widget _host({
  required CustomScoreController controller,
  required ValueChanged<CustomScore> onPlay,
  required VoidCallback onOpenLibrary,
  Future<List<XFile>> Function()? pick,
  PreviewNotes? previewNotes,
  required void Function(ScoreImportFlow) onFlow,
}) {
  final flow = ScoreImportFlow(
    controller: controller,
    onPlay: onPlay,
    onOpenLibrary: onOpenLibrary,
    previewNotes: previewNotes ?? (_) => const [StaffNote(60, 0, 1)],
    pickFiles: pick ?? () async => const [],
  );
  onFlow(flow);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Builder(
      builder: (context) => Scaffold(
        body: Column(
          children: [
            TextButton(
              onPressed: () => flow.pickAndImport(context),
              child: const Text('pick'),
            ),
            TextButton(
              onPressed: () => flow.importFiles(context, [
                _file('a.abc'),
                _file('notes.txt'),
                _file('bad.abc'),
                _file('empty.abc', size: 0),
              ]),
              child: const Text('drop-mixed'),
            ),
            TextButton(
              onPressed: () =>
                  flow.importFiles(context, [_file('a.abc'), _file('b.abc')]),
              child: const Text('drop-two'),
            ),
            TextButton(
              onPressed: () => flow.importFiles(context, [_file('a.abc')]),
              child: const Text('drop-one'),
            ),
          ],
        ),
      ),
    ),
  );
}

Finder textCI(String s) => find.byWidgetPredicate(
  (w) => w is Text && (w.data ?? '').toLowerCase() == s.toLowerCase(),
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('one picked file opens its preview, and Practice plays it', (
    tester,
  ) async {
    final c = _controller();
    await c.load();
    CustomScore? played;
    await tester.pumpWidget(
      _host(
        controller: c,
        onPlay: (s) => played = s,
        onOpenLibrary: () {},
        pick: () async => [_file('twinkle.abc')],
        onFlow: (_) {},
      ),
    );

    await tester.tap(find.text('pick'));
    await _settle(tester);
    expect(find.text('Song twinkle'), findsOneWidget);

    await tester.tap(textCI('Practice'));
    await _settle(tester);
    expect(played?.id, 'twinkle');
    expect(c.scores, hasLength(1));
  });

  testWidgets('cancelling the picker does nothing', (tester) async {
    final c = _controller();
    await c.load();
    await tester.pumpWidget(
      _host(
        controller: c,
        onPlay: (_) {},
        onOpenLibrary: () {},
        onFlow: (_) {},
      ),
    );
    await tester.tap(find.text('pick'));
    await _settle(tester);
    expect(find.byType(GamePanel), findsNothing);
    expect(c.scores, isEmpty);
  });

  testWidgets('a mixed drop lists what was added and why the rest were not', (
    tester,
  ) async {
    final c = _controller();
    await c.load();
    await tester.pumpWidget(
      _host(
        controller: c,
        onPlay: (_) {},
        onOpenLibrary: () {},
        onFlow: (_) {},
      ),
    );

    await tester.tap(find.text('drop-mixed'));
    await _settle(tester);

    expect(find.text('1 score added'), findsOneWidget);
    expect(find.text('Not added'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.textContaining('Not a score file'), findsOneWidget);
    expect(find.textContaining('No notes found'), findsOneWidget);
    expect(find.textContaining('The file is empty'), findsOneWidget);
    // Plain language: never the parser's own text or an exception name.
    expect(find.textContaining('abc: no notes'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(c.scores.map((s) => s.id), ['a']);
  });

  testWidgets('two files drop to a summary, and Open library asks for it', (
    tester,
  ) async {
    final c = _controller();
    await c.load();
    var opened = 0;
    await tester.pumpWidget(
      _host(
        controller: c,
        onPlay: (_) {},
        onOpenLibrary: () => opened++,
        onFlow: (_) {},
      ),
    );

    await tester.tap(find.text('drop-two'));
    await _settle(tester);
    expect(find.text('2 scores added'), findsOneWidget);
    expect(find.text('Song a'), findsOneWidget);
    expect(find.text('Song b'), findsOneWidget);

    await tester.tap(textCI('Open library'));
    await _settle(tester);
    expect(opened, 1);
  });

  testWidgets('dropping the same file twice says it is already there', (
    tester,
  ) async {
    final c = _controller();
    await c.load();
    await tester.pumpWidget(
      _host(
        controller: c,
        onPlay: (_) {},
        onOpenLibrary: () {},
        onFlow: (_) {},
      ),
    );

    await tester.tap(find.text('drop-one'));
    await _settle(tester);
    await tester.tap(textCI('Close'));
    await _settle(tester);
    await tester.tap(find.text('drop-one'));
    await _settle(tester);

    expect(find.textContaining('already in your library'), findsOneWidget);
    expect(c.scores, hasLength(1));
  });

  test('the summary is needed for failures and for several scores only', () {
    CustomScore score(String id) => CustomScore(
      id: id,
      title: id,
      composer: 'c',
      fileName: '$id.mid',
      bars: 1,
      timeSignature: '4/4',
      songJson: '{}',
      importedAt: DateTime.utc(2026),
    );
    expect(
      needsImportSummary(
        ImportOutcome(imported: [score('a')], failures: const []),
      ),
      isFalse,
    );
    expect(
      needsImportSummary(
        ImportOutcome(imported: [score('a'), score('b')], failures: const []),
      ),
      isTrue,
    );
    expect(
      needsImportSummary(
        const ImportOutcome(
          imported: [],
          failures: [ImportFailure('x.txt', ImportProblem.unsupportedType)],
        ),
      ),
      isTrue,
    );
  });
}
