import 'dart:io';

import 'package:easy_piano/content/content_repo.dart';
import 'package:easy_piano/home/home_page.dart';
import 'package:easy_piano/input/midi_input.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:easy_piano/methods/method_page.dart';
import 'package:easy_piano/methods/methods_library_page.dart';
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

    // Scroll down so the Methods card is fully centered in view.
    final methodsCardFinder = find.text('METHODS');
    await tester.scrollUntilVisible(
      methodsCardFinder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // Drag an extra 250px up so it is well clear of the bottom navigation bar.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
    await tester.pump(const Duration(milliseconds: 600));
    expect(methodsCardFinder, findsOneWidget);

    // Tap Methods card to open Methods Library.
    await tester.tap(methodsCardFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(MethodsLibraryPage), findsOneWidget);
    expect(find.text('Mikrokosmos'), findsOneWidget);
    expect(find.text('BÉLA BARTÓK'), findsOneWidget);

    // Filter chips work.
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Beginner'), findsOneWidget);
    await tester.tap(find.text('Beginner'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Mikrokosmos'), findsOneWidget);

    // Tap Mikrokosmos method card to open MethodPage.
    await tester.tap(find.text('Mikrokosmos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(MethodPage), findsOneWidget);

    // MethodPage has description, Continue button, and book sections.
    expect(find.textContaining('153 progressive piano pieces'), findsOneWidget);
    expect(find.text('CONTINUE'), findsOneWidget);
    expect(find.text('Mikrokosmos I'), findsOneWidget);

    // First piece is visible in the continue banner and the first open book.
    expect(find.text('Six Unison Melodies, No. 1'), findsNWidgets(2));

    // Tapping a piece opens TaskSheet.
    await tester.tap(find.text('Six Unison Melodies, No. 1').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('PLAY'), findsOneWidget);

    // Close bottom sheet.
    Navigator.of(tester.element(find.text('PLAY'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('PLAY'), findsNothing);

    // Back from MethodPage returns to MethodsLibraryPage.
    final backButtons = find.byType(IconButton);
    await tester.tap(backButtons.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(MethodsLibraryPage), findsOneWidget);

    // Back from MethodsLibraryPage returns to LearnTab.
    await tester.tap(find.byType(IconButton).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(MethodsLibraryPage), findsNothing);

    // Scroll back up to the top so top switcher is below the floating top bar.
    final topMethodsSwitcher = find.text('Methods');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1000));
    await tester.pump(const Duration(milliseconds: 600));
    expect(topMethodsSwitcher, findsOneWidget);
    await tester.tap(topMethodsSwitcher);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(MethodsLibraryPage), findsOneWidget);

    // Return to LearnTab.
    await tester.tap(find.byType(IconButton).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(MethodsLibraryPage), findsNothing);

    // Collapsible sections work on the main path.
    await tester.scrollUntilVisible(
      find.text('SOLOIST'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -100));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('SOLOIST'), findsOneWidget);
    await tester.tap(find.text('SOLOIST'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  });
}
