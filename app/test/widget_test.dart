import 'dart:ui';

import 'package:easy_piano/ui/key_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final g = KeyGeometry(lowPitch: 48, highPitch: 84, size: const Size(220, 100));

  test('C3..C6 has 22 white keys', () {
    expect(g.whiteWidth, closeTo(10, 1e-9));
  });

  test('black keys are detected', () {
    expect(KeyGeometry.isBlack(61), isTrue); // C#4
    expect(KeyGeometry.isBlack(64), isFalse); // E4
  });

  test('black key hit wins over white key below it', () {
    final cSharp = g.keyRect(49);
    expect(g.pitchAt(cSharp.center), 49);
  });

  test('low white area resolves to white key', () {
    expect(g.pitchAt(const Offset(5, 90)), 48);
  });
}
