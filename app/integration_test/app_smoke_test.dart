// Boots the real app (Rust library, content, locale) to the home screen.
// Catches packaging bugs that unit tests can't: a missing ABI, a native
// library that fails to load, assets left out of the bundle. CI runs it on
// an Android emulator; locally: flutter test integration_test/app_smoke_test.dart
import 'package:easy_piano/home/home_page.dart';
import 'package:easy_piano/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app starts on the home screen', (tester) async {
    await app.main();
    for (var i = 0; i < 100 && find.byType(HomePage).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(HomePage), findsOneWidget);
    // The music font loads after the first frame and relayouts text; let
    // that land before the test tears the tree down.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}
