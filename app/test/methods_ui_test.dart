import 'dart:io';

import 'package:easy_piano/content/content_repo.dart';
import 'package:easy_piano/home/home_page.dart';
import 'package:easy_piano/input/midi_input.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:easy_piano/methods/methods_library_page.dart';
import 'package:easy_piano/ui/game/game_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ContentRepo _repo() {
  final root = Directory('../content').absolute;
  final files = {
    for (final f in root.listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.json') && !f.path.contains('schema'))
        f.uri.pathSegments.skip(root.uri.pathSegments.length - 1).join('/'): f
            .readAsStringSync(),
  };
  return ContentRepo.fromFiles(files);
}

void main() {
  testWidgets('Methods library flow: card, library, method page, piece', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = _repo();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomePage(
          repo: repo,
          midi: createMidiInput(),
          spikes: (_) => const SizedBox(),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    // Switch to Methods using the top switcher.
    final methodsSwitchFinder = find.text('METHODS');
    expect(methodsSwitchFinder, findsOneWidget);
    await tester.tap(methodsSwitchFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(MethodsCatalogView), findsOneWidget);
    expect(find.text('MIKROKOSMOS'), findsOneWidget);
    expect(find.textContaining('BÉLA BARTÓK'), findsOneWidget);

    // Filter chips work: LEVEL and SKILL rows both have 'All'
    expect(find.text('All'), findsNWidgets(2));
    expect(find.text('Beginner'), findsOneWidget);
    await tester.tap(find.text('Beginner'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('MIKROKOSMOS'), findsOneWidget);

    // Tap Mikrokosmos method card to expand inline like a course module.
    await tester.tap(find.text('MIKROKOSMOS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    // Mikrokosmos expands inline to show its books and pieces.
    expect(find.text('MIKROKOSMOS I'), findsOneWidget);
    expect(find.text('Six Unison Melodies, No. 1'), findsOneWidget);

    // Tapping a piece opens TaskSheet.
    await tester.tap(find.text('Six Unison Melodies, No. 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.widgetWithText(GameButton, 'PRACTICE'), findsOneWidget);
    expect(find.text('PLAY ALONG'), findsOneWidget);

    // Close bottom sheet.
    Navigator.of(tester.element(find.text('PLAY ALONG'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('PLAY ALONG'), findsNothing);

    // Switch back to Courses using the top switcher.
    final topCoursesSwitcher = find.text('COURSES');
    expect(topCoursesSwitcher, findsOneWidget);
    await tester.tap(topCoursesSwitcher);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(MethodsCatalogView), findsNothing);

    // Switch to Methods using the top switcher.
    final topMethodsSwitcher = find.text('METHODS');
    expect(topMethodsSwitcher, findsOneWidget);
    await tester.tap(topMethodsSwitcher);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(MethodsCatalogView), findsOneWidget);

    // Switch back to Courses.
    await tester.tap(topCoursesSwitcher);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(MethodsCatalogView), findsNothing);

    // Collapsible sections work on the main path.
    await tester.scrollUntilVisible(
      find.text('SOLOIST'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('SOLOIST'), findsOneWidget);
    await tester.tap(find.text('SOLOIST'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('LearnTab renders without overflow on narrow phone viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = _repo();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomePage(
          repo: repo,
          midi: createMidiInput(),
          spikes: (_) => const SizedBox(),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}
