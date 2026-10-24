import 'package:easy_piano/ui/window/window_title_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

  // Mirrors MaterialApp.builder: controls float above the Navigator with no
  // Scaffold or Overlay around them.
  Future<void> pumpControls(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => Stack(
        children: [
          child!,
          Positioned(top: 0, right: 0, child: WindowControls(channel: channel)),
        ],
      ),
      home: const SizedBox.expand(),
    ),
  );

  testWidgets('caption buttons call the window channel', (tester) async {
    await pumpControls(tester);

    await tester.tap(find.byKey(const Key('window-minimize')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('window-maximize')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('window-close')));
    await tester.pump();

    expect(calls, containsAllInOrder(['minimize', 'toggleMaximize', 'close']));
  });

  testWidgets('hovering a caption button does not throw (no Overlay needed)', (
    tester,
  ) async {
    await pumpControls(tester);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    for (final key in ['window-minimize', 'window-maximize', 'window-close']) {
      await gesture.moveTo(tester.getCenter(find.byKey(Key(key))));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('maximize icon reflects maximized state', (tester) async {
    maximized = true;
    await pumpControls(tester);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.filter_none), findsOneWidget);
    expect(find.byIcon(Icons.crop_square), findsNothing);
  });

  testWidgets('drag area starts a window drag and passes taps through', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: WindowDragArea(
            channel: channel,
            child: GestureDetector(
              onTap: () => tapped = true,
              child: Container(
                key: const Key('drag-target'),
                width: 100,
                height: 40,
                color: Colors.red,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('drag-target')));
    // Double-tap recognition waits out the double-tap window before a tap.
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, isTrue);

    await tester.drag(
      find.byKey(const Key('drag-target')),
      const Offset(40, 0),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, contains('startDrag'));
  });
}
