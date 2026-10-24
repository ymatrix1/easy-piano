import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_piano/ui/staff/engraving_decorations.dart';

void main() {
  group('EngravingDecorations (MuseScore slurtielayout.cpp style)', () {
    testWidgets('drawTie executes cleanly without error', (tester) async {
      await tester.pumpWidget(
        CustomPaint(size: const Size(200, 100), painter: _TestTiePainter()),
      );
      expect(find.byType(CustomPaint), findsOneWidget);
    });

    testWidgets(
      'drawArticulation executes cleanly for staccato, tenuto, accent',
      (tester) async {
        await tester.pumpWidget(
          CustomPaint(
            size: const Size(200, 100),
            painter: _TestArticulationPainter(),
          ),
        );
        expect(find.byType(CustomPaint), findsOneWidget);
      },
    );
  });
}

class _TestTiePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    EngravingDecorations.drawTie(
      canvas,
      x1: 20,
      y1: 50,
      x2: 80,
      y2: 50,
      space: 10,
      color: Colors.black,
      tieAbove: false,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TestArticulationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    EngravingDecorations.drawArticulation(
      canvas,
      articulation: 'staccato',
      x: 20,
      y: 50,
      space: 10,
      color: Colors.black,
      stemDown: false,
    );
    EngravingDecorations.drawArticulation(
      canvas,
      articulation: 'tenuto',
      x: 50,
      y: 50,
      space: 10,
      color: Colors.black,
      stemDown: true,
    );
    EngravingDecorations.drawArticulation(
      canvas,
      articulation: 'accent',
      x: 80,
      y: 50,
      space: 10,
      color: Colors.black,
      stemDown: false,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
