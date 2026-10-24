import 'package:easy_piano/ui/staff/score_page_view.dart';
import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:easy_piano/ui/staff/staff_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScorePageView Widget Test', () {
    testWidgets('renders score page view with title, pages and controls', (
      tester,
    ) async {
      final notes = List.generate(
        16,
        (i) => StaffNote(60 + i, i * 1.0, 1.0, leftHand: i.isOdd),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ScorePageView(
            notes: notes,
            totalBeats: 16.0,
            beatsPerBar: 4.0,
            keyFifths: 0,
            staves: Staves.grand,
            title: 'Für Elise',
            composer: 'L. v. Beethoven',
          ),
        ),
      );

      expect(find.text('Für Elise'), findsWidgets);
      expect(find.text('L. v. Beethoven'), findsWidgets);
      expect(find.byIcon(Icons.zoom_in), findsOneWidget);
      expect(find.byIcon(Icons.zoom_out), findsOneWidget);
      expect(find.textContaining('Page 1 /'), findsOneWidget);
    });
  });
}
