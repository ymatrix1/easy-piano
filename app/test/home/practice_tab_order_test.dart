import 'package:easy_piano/home/other_tabs.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the song library card comes before the coming-soon cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: PracticeTab(
            onFreePlay: () {},
            onEndless: () {},
            onSongLibrary: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    double top(String text) => tester
        .getTopLeft(
          find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? '').toLowerCase() == text,
          ),
        )
        .dy;
    final library = top('song library');
    expect(library, lessThan(top('sight reading')));
    expect(library, lessThan(top('rhythm drills')));
    expect(library, greaterThan(top('endless practice')));
  });
}
