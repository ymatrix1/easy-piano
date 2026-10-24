import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:easy_piano/ui/window/window_title_bar.dart';

void main() {
  const channel = MethodChannel('test/easy_piano_window');
  final calls = <String>[];
  var maximized = false;

  setUp(() {
    calls.clear();
    maximized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'isMaximized') return maximized;
          if (call.method == 'toggleMaximize') maximized = !maximized;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpBar(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: WindowTitleBar(channel: channel)),
    ),
  );

  testWidgets('caption buttons call the window channel', (tester) async {
    await pumpBar(tester);

    await tester.tap(find.byKey(const Key('window-minimize')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('window-maximize')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('window-close')));
    await tester.pump();

    expect(calls, containsAllInOrder(['minimize', 'toggleMaximize', 'close']));
  });

  testWidgets('maximize icon reflects maximized state', (tester) async {
    maximized = true;
    await pumpBar(tester);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.filter_none), findsOneWidget);
    expect(find.byIcon(Icons.crop_square), findsNothing);
  });

  testWidgets('bar is 36 logical pixels tall', (tester) async {
    await pumpBar(tester);
    expect(tester.getSize(find.byType(WindowTitleBar)).height, kTitleBarHeight);
  });
}
