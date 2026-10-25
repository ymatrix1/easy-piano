import 'package:easy_piano/custom/custom_score.dart';
import 'package:easy_piano/custom/score_drop_zone.dart';
import 'package:easy_piano/custom/score_preview.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  test('only score files are kept from a drop', () {
    final files = [
      XFile('a.mxl'),
      XFile('photo.png'),
      XFile('b.MID'),
      XFile('notes.txt'),
    ];
    expect(supportedScoreFiles(files).map((f) => f.name), ['a.mxl', 'b.MID']);
  });

  testWidgets('overlay shows the drop hint only while a drag hovers', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const Stack(children: [ScoreDropOverlay(visible: false)])),
    );
    expect(textCI('Drop score file to import'), findsNothing);

    await tester.pumpWidget(
      _app(const Stack(children: [ScoreDropOverlay(visible: true)])),
    );
    expect(textCI('Drop score file to import'), findsOneWidget);
  });

  testWidgets('preview shows metadata and Practice starts the score', (
    tester,
  ) async {
    final score = CustomScore(
      id: 'ode',
      title: 'Ode to Joy',
      composer: 'Beethoven',
      fileName: 'ode.mid',
      bars: 16,
      timeSignature: '3/4',
      songJson: '{}',
      importedAt: DateTime.utc(2026),
    );
    var played = false;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showScorePreview(context, score, onPlay: () => played = true),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Beethoven'), findsOneWidget);
    expect(find.text('16 bars  ·  Time 3/4'), findsOneWidget);

    await tester.tap(textCI('Practice'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(played, isTrue);
    expect(find.text('Beethoven'), findsNothing);
  });
}
