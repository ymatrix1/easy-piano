import 'package:easy_piano/src/rust/api/notation.dart';
import 'package:easy_piano/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  test('Rust core parses pitch through the bridge', () {
    expect(parsePitch(token: 'C4'), 60);
    expect(pitchName(midi: 61), 'C#4');
    expect(() => parsePitch(token: 'H4'), throwsA(anything));
  });
}
