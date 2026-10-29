import 'package:easy_piano/custom/score_drop_zone.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: home,
);

Finder textCI(String s) => find.byWidgetPredicate(
  (w) => w is Text && (w.data ?? '').toLowerCase() == s.toLowerCase(),
);

void main() {
  testWidgets('overlay shows the drop hint only while a drag hovers', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const Stack(children: [ScoreDropOverlay(visible: false)])),
    );
    expect(textCI('Drop score file to import'), findsNothing);

    await tester.pumpWidget(
      _app(const Stack(children: [ScoreDropOverlay(visible: true)])),
    );
    expect(textCI('Drop score file to import'), findsOneWidget);
  });
}
