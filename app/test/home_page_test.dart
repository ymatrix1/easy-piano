import 'dart:io';

import 'package:easy_piano/content/content_repo.dart';
import 'package:easy_piano/home/home_page.dart';
import 'package:easy_piano/input/midi_input.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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
  testWidgets('menu: modules, collapsible inner trail, tabs', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _repo();
    final router = GoRouter(
      initialLocation: '/learn',
      routes: [
        for (final tab in ['learn', 'practice', 'profile'])
          GoRoute(
            path: '/$tab',
            builder: (_, _) => HomePage(
              repo: repo,
              midi: createMidiInput(),
              spikes: (_) => const SizedBox(),
              tab: tab,
            ),
          ),
        GoRoute(path: '/tool', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/lesson/:levelId', builder: (_, _) => const SizedBox()),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    // Outer trail: Piano Basics open, all three Essentials ready.
    expect(find.text('PIANO BASICS'), findsOneWidget);
    expect(find.text('ESSENTIALS I'), findsOneWidget);
    expect(find.text('COMING SOON'), findsNothing);
    // Inner trail of the current module is expanded.
    expect(find.text('2. C, D and E'), findsOneWidget);

    // Collapse it.
    await tester.tap(find.text('PIANO BASICS'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2. C, D and E'), findsNothing);

    // Expand again and open a submodule with both wait and play_along stages.
    await tester.tap(find.text('PIANO BASICS'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2. C, D and E'), findsOneWidget);

    await tester.tap(find.text('2. C, D and E'));
    await tester.pump(const Duration(milliseconds: 600));
    // In the task sheet modal, both Practice and Play along buttons are present.
    // (One "PRACTICE" is the bottom nav tab label, one is the sheet button).
    expect(find.text('PRACTICE'), findsNWidgets(2));
    expect(find.text('PLAY ALONG'), findsOneWidget);

    // Dismiss bottom sheet.
    Navigator.of(tester.element(find.text('PLAY ALONG'))).pop();
    await tester.pump(const Duration(milliseconds: 600));

    // Switch tabs.
    await tester.tap(find.text('PRACTICE'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('FREE PLAY'), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/practice');
    await tester.tap(find.text('PROFILE'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('DEVELOPER TOOLS'), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/profile');
    // Let delayed entrance animations finish.
    await tester.pump(const Duration(seconds: 3));
  });
}
