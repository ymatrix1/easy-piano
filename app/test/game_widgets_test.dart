import 'package:easy_piano/ui/game/game_theme.dart';
import 'package:easy_piano/ui/game/game_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('GameButton shows uppercase label and taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        Center(
          child: GameButton(label: 'Play', onTap: () => taps++),
        ),
      ),
    );
    expect(find.text('PLAY'), findsOneWidget);
    await tester.tap(find.byType(GameButton));
    await tester.pump(const Duration(seconds: 1));
    expect(taps, 1);
  });

  testWidgets('disabled buttons ignore taps', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const Column(
          children: [
            GameRoundButton(icon: Icons.lock, onTap: null),
            GameButton(label: 'Locked', onTap: null),
          ],
        ),
      ),
    );
    await tester.tap(find.byType(GameRoundButton));
    await tester.tap(find.byType(GameButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('StarRow, CountUp and ribbon settle to their end state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const Column(
          children: [
            StarRow(stars: 2.5),
            CountUp(value: 42),
            PopIn(child: GameRibbon('Completed!', tone: GameTone.green)),
            GameProgressBar(value: 0.5),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('42'), findsOneWidget);
    expect(find.text('COMPLETED!'), findsOneWidget);
    // 3 empty sockets + 3 filled (the last one half).
    expect(find.byType(GameStar), findsNWidgets(6));
  });

  testWidgets('reduced motion stops idle loops', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _wrap(
          Center(
            child: GameButton(label: 'Go', onTap: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('GO'), findsOneWidget);
  });

  test('starPath is one closed contour', () {
    final m = starPath(const Rect.fromLTWH(0, 0, 10, 10)).computeMetrics();
    expect(m.length, 1);
  });
}
