import 'dart:io';

import 'package:easy_piano/content/content_repo.dart';
import 'package:easy_piano/home/home_page.dart';
import 'package:easy_piano/input/midi_input.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
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
  testWidgets('menu: modules, collapsible inner trail, tabs', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomePage(
          repo: _repo(),
          midi: createMidiInput(),
          spikes: (_) => const SizedBox(),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    // Outer trail: Piano Basics open, Essentials I ready, II and III planned.
    expect(find.text('PIANO BASICS'), findsOneWidget);
    expect(find.text('ESSENTIALS I'), findsOneWidget);
    expect(find.text('COMING SOON'), findsNWidgets(2));
    // Inner trail of the current module is expanded.
    expect(find.text('2. C, D and E'), findsOneWidget);

    // Collapse it.
    await tester.tap(find.text('PIANO BASICS'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2. C, D and E'), findsNothing);

    // Switch tabs.
    await tester.tap(find.text('PRACTICE'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('FREE PLAY'), findsOneWidget);
    await tester.tap(find.text('PROFILE'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('DEVELOPER TOOLS'), findsOneWidget);
    // Let delayed entrance animations finish.
    await tester.pump(const Duration(seconds: 3));
  });
}
