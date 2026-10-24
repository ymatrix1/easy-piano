import 'dart:io';

import 'package:easy_piano/content/content_repo.dart';
import 'package:easy_piano/home/home_page.dart';
import 'package:easy_piano/input/midi_input.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:easy_piano/ui/game/game_widgets.dart';
import 'package:flutter/foundation.dart';
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
  // Regression: a flexible title pushed the star counter into the middle of
  // the header. It must sit on the right edge of the tab content column.
  testWidgets('star counter aligns with the content column', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1280, 720);
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
    await tester.pump(const Duration(seconds: 1));

    // Tab content column: ConstrainedBox(maxWidth: homeMaxWidth).
    final column = find.byWidgetPredicate(
      (w) => w is ConstrainedBox && w.constraints.maxWidth == 768,
    );
    expect(column, findsWidgets);
    final columnRight = tester.getRect(column.first).right;
    final starRight = tester.getRect(find.byType(StarCounter)).right;
    expect(starRight, closeTo(columnRight, 1));

    debugDefaultTargetPlatformOverride = null;
  });
}
