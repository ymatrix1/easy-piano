import 'dart:convert';

import 'package:easy_piano/custom/custom_score.dart';
import 'package:easy_piano/custom/custom_score_controller.dart';
import 'package:easy_piano/custom/song_library_page.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStorage implements ScoreStorage {
  List<String> entries = [];

  @override
  Future<List<String>> read() async => entries;

  @override
  Future<void> write(List<String> e) async => entries = [...e];
}

CustomScore _score(String id, String title, String composer) => CustomScore(
  id: id,
  title: title,
  composer: composer,
  fileName: '$id.mid',
  bars: 8,
  timeSignature: '4/4',
  songJson: jsonEncode({'id': id}),
  importedAt: DateTime.utc(2026),
);

Future<CustomScoreController> _loaded(List<CustomScore> scores) async {
  final storage = _MemoryStorage()
    ..entries = [for (final s in scores) jsonEncode(s.toJson())];
  final c = CustomScoreController(
    storage: storage,
    importer: (name, data) async => throw UnimplementedError(),
  );
  await c.load();
  return c;
}

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: home,
);

Finder textCI(String s) => find.byWidgetPredicate(
  (w) => w is Text && (w.data ?? '').toLowerCase() == s.toLowerCase(),
);

void main() {
  testWidgets('shows the empty message when nothing is imported', (
    tester,
  ) async {
    final c = await _loaded([]);
    await tester.pumpWidget(
      _app(SongLibraryPage(controller: c, onPlay: (_) {}, onImport: () {})),
    );
    await tester.pump();

    expect(find.textContaining('No imported scores yet'), findsOneWidget);
  });

  testWidgets('lists scores and searches them by title and composer', (
    tester,
  ) async {
    final c = await _loaded([
      _score('ode', 'Ode to Joy', 'Beethoven'),
      _score('moon', 'Moonlight', 'Beethoven'),
      _score('clair', 'Clair de lune', 'Debussy'),
    ]);
    await tester.pumpWidget(
      _app(SongLibraryPage(controller: c, onPlay: (_) {}, onImport: () {})),
    );
    await tester.pump();

    expect(find.text('Ode to Joy'), findsOneWidget);
    expect(find.text('Clair de lune'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'beethoven');
    await tester.pump();
    expect(find.text('Ode to Joy'), findsOneWidget);
    expect(find.text('Moonlight'), findsOneWidget);
    expect(find.text('Clair de lune'), findsNothing);

    await tester.enterText(find.byType(TextField), 'xyz');
    await tester.pump();
    expect(find.textContaining('No score matches'), findsOneWidget);
  });

  testWidgets('practice button opens the score', (tester) async {
    final c = await _loaded([_score('ode', 'Ode to Joy', 'Beethoven')]);
    CustomScore? played;
    await tester.pumpWidget(
      _app(
        SongLibraryPage(
          controller: c,
          onPlay: (s) => played = s,
          onImport: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(textCI('Practice'));
    await tester.pump();

    expect(played?.id, 'ode');
  });

  testWidgets('delete asks first and removes the score only on confirm', (
    tester,
  ) async {
    final c = await _loaded([
      _score('ode', 'Ode to Joy', 'Beethoven'),
      _score('clair', 'Clair de lune', 'Debussy'),
    ]);
    await tester.pumpWidget(
      _app(SongLibraryPage(controller: c, onPlay: (_) {}, onImport: () {})),
    );
    await tester.pump();

    // Cancel keeps it.
    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Remove this score from your library?'), findsOneWidget);
    await tester.tap(textCI('Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.scores, hasLength(2));

    // Delete removes it from the list and the library.
    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(textCI('Delete'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(c.scores.map((s) => s.id), ['clair']);
    expect(find.text('Ode to Joy'), findsNothing);
    expect(find.text('Clair de lune'), findsOneWidget);
  });
}
