import 'package:easy_piano/ui/game/game_theme.dart';
import 'package:easy_piano/ui/game/game_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {GameSkin skin = GameSkin.classic}) => MaterialApp(
  home: GameSkinScope(
    skin: skin,
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('classic GameButton: single uppercase label, taps', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        Center(
          child: GameButton(label: 'Go', onTap: () => taps++),
        ),
      ),
    );
    expect(find.text('GO'), findsOneWidget);
    await tester.tap(find.byType(GameButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('playful GameButton: outlined label drawn twice', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Center(
          child: GameButton(label: 'Go', onTap: () {}),
        ),
        skin: GameSkin.playfulSkin,
      ),
    );
    expect(find.text('Go'), findsNWidgets(2));
  });

  testWidgets('skin defaults to classic without a scope', (tester) async {
    late GameSkin seen;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          seen = GameSkin.of(context);
          return const SizedBox();
        },
      ),
    );
    expect(seen, GameSkin.classic);
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

  for (final skin in GameSkin.all) {
    testWidgets('${skin.id}: StarRow and CountUp settle', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Column(
            children: [
              StarRow(stars: 2.5),
              CountUp(value: 42),
              PopIn(child: GameRibbon('Completed!', tone: GameTone.green)),
            ],
          ),
          skin: skin,
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('42'), findsWidgets);
      // 3 empty sockets + 3 filled (the last one half).
      expect(find.byType(GameStar), findsNWidgets(6));
    });
  }

  test('starPath is one closed contour', () {
    final m = starPath(const Rect.fromLTWH(0, 0, 10, 10)).computeMetrics();
    expect(m.length, 1);
  });
}
