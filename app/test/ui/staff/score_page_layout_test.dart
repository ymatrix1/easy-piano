import 'package:easy_piano/ui/staff/score_page_layout.dart';
import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(
    'ScorePageLayout (MuseScore pagelayout.cpp & scorepageviewlayout.cpp)',
    () {
      test('buildMeasures partitions notes correctly across bar lines', () {
        final notes = [
          const StaffNote(60, 0.0, 1.0), // measure 0
          const StaffNote(62, 1.0, 1.0), // measure 0
          const StaffNote(64, 4.0, 1.0), // measure 1
          const StaffNote(65, 8.0, 1.0), // measure 2
        ];

        final measures = ScorePageLayout.buildMeasures(
          notes: notes,
          beatsPerBar: 4.0,
          totalBeats: 12.0,
        );

        expect(measures.length, equals(3));
        expect(measures[0].index, equals(0));
        expect(measures[0].startBeat, equals(0.0));
        expect(measures[0].endBeat, equals(4.0));
        expect(measures[0].notes.length, equals(2));

        expect(measures[1].index, equals(1));
        expect(measures[1].notes.length, equals(1));

        expect(measures[2].index, equals(2));
        expect(measures[2].notes.length, equals(1));
      });

      test('breakSystems packs measures within printable line limits', () {
        const config = ScorePageConfig(
          pageWidth: 800.0,
          marginLeft: 40.0,
          marginRight: 40.0,
          systemHeaderWidth: 60.0,
          minMeasureWidth: 150.0,
          maxMeasuresPerSystem: 4,
          minMeasuresPerSystem: 2,
        );

        // Printable width = 800 - 80 = 720
        // System measure width = 720 - 60 = 660
        // 4 measures of 150 min width = 600 (< 660) -> fits in 1 system
        final measures = List.generate(
          8,
          (i) => ScoreMeasure(
            index: i,
            startBeat: i * 4.0,
            endBeat: (i + 1) * 4.0,
            notes: const [],
            minWidth: 150.0,
          ),
        );

        final systems = ScorePageLayout.breakSystems(
          measures: measures,
          config: config,
        );

        // 8 measures should break cleanly into 2 systems of 4 measures each
        expect(systems.length, equals(2));
        expect(systems[0].measures.length, equals(4));
        expect(systems[1].measures.length, equals(4));
      });

      test('system justification stretches measures proportionally to fill system width', () {
        const config = ScorePageConfig(
          pageWidth: 800.0,
          marginLeft: 50.0,
          marginRight: 50.0,
          systemHeaderWidth: 50.0,
          minMeasureWidth: 100.0,
          maxMeasuresPerSystem: 3,
          minMeasuresPerSystem: 2,
        );

        // Printable = 700. System measure width = 650.
        final measures = [
          const ScoreMeasure(
            index: 0,
            startBeat: 0.0,
            endBeat: 4.0,
            notes: [],
            minWidth: 100.0,
          ),
          const ScoreMeasure(
            index: 1,
            startBeat: 4.0,
            endBeat: 8.0,
            notes: [],
            minWidth: 200.0,
          ),
          const ScoreMeasure(
            index: 2,
            startBeat: 8.0,
            endBeat: 12.0,
            notes: [],
            minWidth: 100.0,
          ),
        ];

        final systems = ScorePageLayout.breakSystems(
          measures: measures,
          config: config,
        );

        expect(systems.length, equals(1));
        final sys = systems.first;
        expect(sys.measures.length, equals(3));

        // Sum of min widths = 100 + 200 + 100 = 400.
        // Target width = 650. Extra space = 250.
        // Measure 0 gets: 100 + 250 * (100/400) = 100 + 62.5 = 162.5
        // Measure 1 gets: 200 + 250 * (200/400) = 200 + 125 = 325.0
        // Measure 2 gets: 100 + 250 * (100/400) = 100 + 62.5 = 162.5
        // Total = 162.5 + 325.0 + 162.5 = 650.0
        expect(sys.measureWidths[0], closeTo(162.5, 1e-4));
        expect(sys.measureWidths[1], closeTo(325.0, 1e-4));
        expect(sys.measureWidths[2], closeTo(162.5, 1e-4));

        final totalJustified = sys.measureWidths.reduce((a, b) => a + b);
        expect(totalJustified, closeTo(config.systemMeasureWidth, 1e-4));

        // Measure Xs align consecutively
        expect(sys.measureXs[0], equals(0.0));
        expect(sys.measureXs[1], closeTo(162.5, 1e-4));
        expect(sys.measureXs[2], closeTo(487.5, 1e-4));
      });

      test(
        'paginate splits vertical systems across pages based on page height',
        () {
          const config = ScorePageConfig(
            pageHeight: 600.0,
            marginTop: 50.0,
            marginBottom: 50.0,
            grandStaffHeight: 100.0,
            systemDistance: 50.0,
          );

          // Printable height = 500. System height + distance = 150.
          // 500 ~/ 150 = 3 systems per page.
          final systems = List.generate(
            7,
            (i) => ScoreSystem(
              systemIndex: i,
              measures: const [],
              measureWidths: const [],
              measureXs: const [],
              totalWidth: 700.0,
              hasClefAndKey: true,
            ),
          );

          final pages = ScorePageLayout.paginate(
            systems: systems,
            config: config,
          );

          // 7 systems / 3 per page = 3 pages (3, 3, 1)
          expect(pages.length, equals(3));
          expect(pages[0].systems.length, equals(3));
          expect(pages[1].systems.length, equals(3));
          expect(pages[2].systems.length, equals(1));
        },
      );

      test(
        'layoutScore end-to-end creates complete pages from note sequence',
        () {
          final notes = List.generate(
            32,
            (i) => StaffNote(60 + (i % 8), i * 1.0, 1.0, leftHand: i.isOdd),
          );

          final pages = ScorePageLayout.layoutScore(
            notes: notes,
            beatsPerBar: 4.0,
            totalBeats: 32.0,
            config: const ScorePageConfig(pageWidth: 800.0, pageHeight: 1000.0),
          );

          expect(pages.isNotEmpty, isTrue);
          expect(pages.first.systems.isNotEmpty, isTrue);
          expect(pages.first.systems.first.measures.isNotEmpty, isTrue);
        },
      );
    },
  );
}
