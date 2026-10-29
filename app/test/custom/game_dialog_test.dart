import 'package:easy_piano/custom/game_dialog.dart';
import 'package:easy_piano/ui/game/game_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget body, {double maxWidth = 460}) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: TextButton(
        onPressed: () => showGameDialog<void>(
          context,
          maxWidth: maxWidth,
          builder: (_) => body,
        ),
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows its content in a game panel', (tester) async {
    await tester.pumpWidget(_app(const Text('hello')));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GamePanel), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('never wider than the window with a 16 px margin', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const SizedBox(width: 900, height: 10)));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    final r = tester.getRect(find.byType(GamePanel));
    expect(r.left, greaterThanOrEqualTo(16));
    expect(r.right, lessThanOrEqualTo(320 - 16));
  });

  testWidgets('scrolls when the content is taller than the window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(667, 375);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            for (var i = 0; i < 30; i++) Text('line $i'),
            const Text('last'),
          ],
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -2000),
    );
    await tester.pump();
    expect(tester.getRect(find.text('last')).bottom, lessThanOrEqualTo(375));
  });
}
