import 'package:easy_piano/ui/game/game_theme.dart';
import 'package:easy_piano/ui/game/game_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('GameButton taps and shows its label', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        Center(
          child: GameButton(label: 'GO', onTap: () => taps++),
        ),
      ),
    );
    // Label is drawn twice (outline + fill).
    expect(find.text('GO'), findsNWidgets(2));
    await tester.tap(find.byType(GameButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('disabled GameRoundButton ignores taps', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const Center(child: GameRoundButton(icon: Icons.lock, onTap: null)),
      ),
    );
    await tester.tap(find.byType(GameRoundButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('StarRow and CountUp settle to their end state', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const Column(
          children: [
            StarRow(stars: 2.5),
            CountUp(value: 42),
            PopIn(child: GameRibbon('Completed!', tone: GameTone.green)),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('42'), findsNWidgets(2));
    expect(
      find.byType(GameStar),
      findsNWidgets(6),
    ); // 3 sockets + 3 filled (last one half)
  });

  test('starPath has ten points', () {
    final m = starPath(const Rect.fromLTWH(0, 0, 10, 10)).computeMetrics();
    expect(m.length, 1);
  });
}
