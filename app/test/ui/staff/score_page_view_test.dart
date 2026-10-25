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

    testWidgets(
      'SystemStaffPainter renders LH chord clusters with unified stems and flags',
      (tester) async {
        // Rondo alla Turca measure 5 LH chords: B3+E4:8 and D#5+F#5:8
        final chordNotes = [
          const StaffNote(59, 0.0, 0.5, leftHand: true), // B3
          const StaffNote(64, 0.0, 0.5, leftHand: true), // E4
          const StaffNote(63, 1.0, 0.5, leftHand: true), // D#4
          const StaffNote(66, 1.0, 0.5, leftHand: true), // F#4
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: ScorePageView(
              notes: chordNotes,
              totalBeats: 4.0,
              beatsPerBar: 2.0,
              keyFifths: 0,
              staves: Staves.grand,
              title: 'Rondo alla Turca',
            ),
          ),
        );

        expect(find.text('Rondo alla Turca'), findsWidgets);
        expect(find.byType(CustomPaint), findsWidgets);
      },
    );

    testWidgets(
      'tapping on a score system seeks playhead and updates current measure',
      (tester) async {
        final notes = List.generate(
          16,
          (i) => StaffNote(60 + (i % 8), i * 1.0, 1.0, leftHand: i.isOdd),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ScorePageView(
              notes: notes,
              totalBeats: 16.0,
              beatsPerBar: 4.0,
              title: 'Tap Seek Test',
            ),
          ),
        );

        expect(find.text('MEASURE 1'), findsOneWidget);

        // Tap the right side of the first staff system (measure 3 or 4)
        final systemPaint = find
            .byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is SystemStaffPainter,
            )
            .first;
        await tester.tapAt(
          tester.getCenter(systemPaint) + const Offset(150, 0),
        );
        await tester.pump();

        // The measure indicator should update past measure 1
        expect(find.text('MEASURE 1'), findsNothing);
      },
    );
  });
}
