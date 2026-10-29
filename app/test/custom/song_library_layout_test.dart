import 'dart:convert';

import 'package:easy_piano/custom/custom_score.dart';
import 'package:easy_piano/custom/custom_score_controller.dart';
import 'package:easy_piano/custom/import_problem.dart';
import 'package:easy_piano/custom/score_text.dart';
import 'package:easy_piano/custom/song_library_page.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:easy_piano/ui/game/game_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStorage implements ScoreStorage {
  List<String> entries = [];

  @override
  Future<List<String>> read() async => entries;

  @override
  Future<void> write(List<String> e) async => entries = [...e];
}

CustomScore _score(String id, String title) => CustomScore(
  id: id,
  title: title,
  composer: 'A composer with a rather long name, Jr.',
  fileName: '$id.mid',
  bars: 128,
  timeSignature: '12/8',
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

Widget _app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: locale,
  home: home,
);

void main() {
  _libraryTitlesFit();

  testWidgets('the empty library offers to import and shows the rights note', (
    tester,
  ) async {
    final c = await _loaded([]);
    var imports = 0;
    await tester.pumpWidget(
      _app(
        SongLibraryPage(
          controller: c,
          onPlay: (_) {},
          onImport: () => imports++,
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('never uploaded'), findsOneWidget);
    await tester.tap(find.byType(GameButton));
    await tester.pump();
    expect(imports, 1);
  });

  testWidgets('the header import button asks the host to open the picker', (
    tester,
  ) async {
    final c = await _loaded([_score('a', 'A')]);
    var imports = 0;
    await tester.pumpWidget(
      _app(
        SongLibraryPage(
          controller: c,
          onPlay: (_) {},
          onImport: () => imports++,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.upload_file_rounded));
    await tester.pump();
    expect(imports, 1);
  });

  testWidgets('the library has no stock app bar, list tile or alert dialog', (
    tester,
  ) async {
    final c = await _loaded([_score('a', 'A')]);
    await tester.pumpWidget(
      _app(SongLibraryPage(controller: c, onPlay: (_) {}, onImport: () {})),
    );
    await tester.pump();
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(ListTile), findsNothing);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Remove this score from your library?'), findsOneWidget);
  });

  for (final size in const [Size(375, 667), Size(320, 568), Size(1440, 900)]) {
    testWidgets('rows with long text do not overflow at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = await _loaded([
        _score('a', 'A title that is much too long to fit on one line ' * 3),
        _score('b', 'Short'),
      ]);
      await tester.pumpWidget(
        _app(SongLibraryPage(controller: c, onPlay: (_) {}, onImport: () {})),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      for (final panel in tester.widgetList(find.byType(GamePanel)).indexed) {
        final rect = tester.getRect(find.byWidget(panel.$2));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
      }
    });
  }

  testWidgets('a search with no match shows the trimmed query', (tester) async {
    final c = await _loaded([_score('a', 'Alpha')]);
    await tester.pumpWidget(
      _app(SongLibraryPage(controller: c, onPlay: (_) {}, onImport: () {})),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), '  zzz ');
    await tester.pump();
    expect(find.text('No score matches "zzz".'), findsOneWidget);
  });

  group('every language has plain text for every import problem', () {
    for (final locale in AppLocalizations.supportedLocales) {
      testWidgets('$locale', (tester) async {
        late AppLocalizations l;
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) {
                l = AppLocalizations.of(context);
                return const SizedBox();
              },
            ),
            locale: locale,
          ),
        );
        final seen = <String>{};
        for (final p in ImportProblem.values) {
          final text = importProblemText(l, p);
          expect(text.trim(), isNotEmpty, reason: '$locale $p');
          expect(text, isNot(contains('{')), reason: '$locale $p');
          expect(text, isNot(contains('Exception')), reason: '$locale $p');
          expect(seen.add(text), isTrue, reason: '$locale $p repeats a text');
        }
        expect(l.scoreRightsNotice, isNotEmpty);
        expect(l.importAdded(1), isNot(equals(l.importAdded(2))));
        expect(l.scoreKey('G'), contains('G'));
        expect(l.scoreTempo(90), contains('90'));
      });
    }
  });

  testWidgets('Portuguese from Portugal and from Brazil each use one word', (
    tester,
  ) async {
    Future<AppLocalizations> load(Locale locale) async {
      late AppLocalizations l;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              l = AppLocalizations.of(context);
              return const SizedBox();
            },
          ),
          locale: locale,
        ),
      );
      return l;
    }

    String all(AppLocalizations l) => [
      l.importScoreDesc,
      l.importScoreFailed,
      l.importScoreUnsupported,
      l.songLibraryEmpty,
      for (final p in ImportProblem.values) importProblemText(l, p),
    ].join(' ');

    final pt = all(await load(const Locale('pt')));
    final br = all(await load(const Locale('pt', 'BR')));
    expect(pt, isNot(contains('arquivo')));
    expect(br, isNot(contains('ficheiro')));
  });
}

void _libraryTitlesFit() {
  for (final locale in const [Locale('pt'), Locale('de'), Locale('fr')]) {
    testWidgets('the header title shrinks to fit at 375 px in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = await _loaded([_score('a', 'Short')]);
      await tester.pumpWidget(
        _app(
          SongLibraryPage(controller: c, onPlay: (_) {}, onImport: () {}),
          locale: locale,
        ),
      );
      await tester.pump();

      // Regression: the title ended in "..." ("BIBLIOTECA DE MU...").
      final title = find.descendant(
        of: find.byType(FittedBox),
        matching: find.byType(GameText),
      );
      expect(title, findsOneWidget);
      expect(tester.widget<GameText>(title).maxLines, isNull);
      final fitted = tester.getSize(find.byType(FittedBox));
      expect(tester.getSize(title).width * 1.0, greaterThan(0));
      expect(fitted.width, lessThanOrEqualTo(375));
    });
  }

  testWidgets('the bar count and meter may use two lines', (tester) async {
    final c = await _loaded([_score('a', 'Short')]);
    await tester.pumpWidget(
      _app(SongLibraryPage(controller: c, onPlay: (_) {}, onImport: () {})),
    );
    await tester.pump();
    final meta = tester.widget<Text>(find.textContaining('128 bars'));
    expect(meta.maxLines, 2);
  });
}
