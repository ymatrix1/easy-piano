import 'dart:io';

import 'package:easy_piano/content/content_repo.dart';
import 'package:easy_piano/home/home_page.dart';
import 'package:easy_piano/home/learn_tab.dart' show CourseNodePage;
import 'package:easy_piano/input/midi_input.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:easy_piano/ui/game/game_theme.dart';
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
    GoRouter.optionURLReflectsImperativeAPIs = true;
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
        GoRoute(
          path: '/course/:courseId/node/:nodeId',
          builder: (context, state) {
            final course = repo.courses.firstWhere(
              (c) => c.id == state.pathParameters['courseId'],
            );
            final node = course.nodes.firstWhere(
              (n) => n.id == state.pathParameters['nodeId'],
            );
            return CourseNodePage(
              repo: repo,
              course: course,
              node: node,
              onPlay: (id, [stage = 0]) async {
                await context.push('/lesson/$id?stage=$stage');
              },
            );
          },
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
    await tester.pump(const Duration(milliseconds: 1000));
    expect(
      router.routeInformationProvider.value.uri.path,
      '/course/piano-basics/node/c-d-e',
    );
    // The course-node URL opens its task page with Practice and Play along.
    expect(find.text('PRACTICE'), findsOneWidget);
    expect(find.text('PLAY ALONG'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Scaffold && widget.backgroundColor == GameColors.bgDeep,
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('PLAY ALONG'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/lesson/pb-02-c-d-e?stage=2',
    );
    router.pop();
    await tester.pump(const Duration(milliseconds: 400));
    router.pop();
    await tester.pump(const Duration(milliseconds: 600));
    expect(router.routeInformationProvider.value.uri.path, '/learn');

    // Switch tabs.
    await tester.tap(find.text('PRACTICE'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('FREE PLAY'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/practice');
    await tester.tap(find.text('PROFILE'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('DEVELOPER TOOLS'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/profile');
    // Let delayed entrance animations finish.
    await tester.pump(const Duration(seconds: 3));
  });
}
