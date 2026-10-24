import 'dart:typed_data';

import 'package:easy_piano/practice/result_screen.dart';
import 'package:easy_piano/src/rust/api/practice.dart';
import 'package:easy_piano/ui/game/game_widgets.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ResultView _result({required bool passed}) => ResultView(
  passed: passed,
  stars: passed ? 3 : 1,
  hitRatio: 1,
  wrong: 0,
  sections: Float64List(0),
  threshold: 0.7,
  suggestPractice: false,
  notesHit: passed ? 10 : 6,
  notesTotal: 10,
  timing: 0.8,
  assists: 1,
  score: 1,
  starsExact: passed ? 3 : 1.5,
  dynamicsPassed: 0,
  dynamicsTotal: 0,
  hairpinsPassed: 0,
  hairpinsTotal: 0,
);

Future<void> _pump(
  WidgetTester tester,
  ResultView r,
  String type, {
  VoidCallback? onNext,
  VoidCallback? onRetry,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ResultScreen(
          result: r,
          stageType: type,
          songTitle: 'Five-finger walk',
          onRetry: onRetry ?? () {},
          onNext: onNext ?? () {},
        ),
      ),
    ),
  );
  // Entrances start on timers; step frames until counters settle.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('passed: title, notes, retry and next work', (tester) async {
    var next = 0, retry = 0;
    await _pump(
      tester,
      _result(passed: true),
      'wait',
      onNext: () => next++,
      onRetry: () => retry++,
    );
    expect(find.text('COMPLETED!'), findsOneWidget);
    expect(find.text('10/10'), findsOneWidget);
    expect(find.text('TIMING'), findsNothing); // wait stages show notes only
    await tester.tap(find.text('NEXT'));
    await tester.tap(find.byType(GameRoundButton));
    await tester.pump(const Duration(seconds: 1));
    expect((next, retry), (1, 1));
  });

  testWidgets('failed play-along: three stats, next locked', (tester) async {
    var next = 0;
    await _pump(
      tester,
      _result(passed: false),
      'play_along',
      onNext: () => next++,
    );
    expect(find.text('ALMOST THERE!'), findsOneWidget);
    expect(find.text('TIMING'), findsOneWidget);
    expect(find.text('ASSISTS'), findsOneWidget);
    await tester.tap(find.text('LOCKED'));
    await tester.pump(const Duration(seconds: 1));
    expect(next, 0);
  });
}
