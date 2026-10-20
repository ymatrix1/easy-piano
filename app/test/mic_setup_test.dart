import 'package:easy_piano/input/mic/mic_input.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:easy_piano/practice/mic_setup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final active in [false, true]) {
    testWidgets('setup panel lays out on a phone (active: $active)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () => showMicSetup(c, micInput, active: active),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      final cal = tester.getRect(find.text('CALIBRATE'));
      final cont = tester.getRect(find.text('CONTINUE'));
      final left = tester.getRect(find.text(active ? 'TURN OFF' : 'CANCEL'));
      // Calibrate above; the two actions side by side on one row.
      expect(cal.top, lessThan(cont.top));
      expect((left.center.dy - cont.center.dy).abs(), lessThan(2));
      expect(left.center.dx, lessThan(cont.center.dx));
      // Close the panel so its timers stop.
      await tester.tap(find.text(active ? 'TURN OFF' : 'CANCEL'));
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
