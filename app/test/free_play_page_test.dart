import 'package:easy_piano/input/midi_input.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:easy_piano/practice/free_play_page.dart';
import 'package:easy_piano/ui/keyboard_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('free play: touch shows the note name, octave buttons shift', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FreePlayPage(midi: createMidiInput()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Play any key'), findsOneWidget);
    expect(find.text('C3 – C6'), findsOneWidget);

    // Bottom-left of the keyboard is the lowest white key: C3.
    final box = tester.getRect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is KeyboardPainter,
      ),
    );
    final g = await tester.startGesture(box.bottomLeft + const Offset(4, -10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Play any key'), findsNothing);
    expect(find.text('C3'), findsWidgets);
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Play any key'), findsOneWidget);

    await tester.tap(find.byTooltip('Higher octave'));
    await tester.pump();
    expect(find.text('C4 – C7'), findsOneWidget);
  });
}
