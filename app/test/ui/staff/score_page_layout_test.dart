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

      test('buildMeasures uses explicit variable measure starts', () {
        final notes = [
          const StaffNote(60, 0, 1),
          const StaffNote(62, 4, 1),
          const StaffNote(64, 7, 1),
        ];
        final measures = ScorePageLayout.buildMeasures(
          notes: notes,
          beatsPerBar: 4,
          totalBeats: 10,
          measureStarts: const [0, 4, 7, 10],
        );
        expect(measures.map((m) => (m.startBeat, m.endBeat)), [
          (0.0, 4.0),
          (4.0, 7.0),
          (7.0, 10.0),
        ]);
        expect(measures.map((m) => m.notes.single.pitch), [60, 62, 64]);
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

      test('layoutMeasureNotes provides collision-free coordinates and barline clearance (MuseScore measurelayout.cpp)', () {
        // Notes in measure with chord second and flat accidental (The Entertainer measure 5)
        final notes = [
          const StaffNote(55, 16.0, 1.0, leftHand: true), // G3
          const StaffNote(
            58,
            16.0,
            1.0,
            leftHand: true,
            accidental: 'flat',
          ), // Bb3
          const StaffNote(60, 16.0, 1.0, leftHand: true), // C4
          const StaffNote(64, 17.0, 1.0), // E4
        ];

        final res = ScorePageLayout.layoutMeasureNotes(
          allNotes: notes,
          measureNoteIndices: const [0, 1, 2, 3],
          measureStartBeat: 16.0,
          measureEndBeat: 20.0,
          measureLeft: 100.0,
          measureWidth: 200.0,
          chordHeadOffsets: const {0: 0.0, 1: -11.8, 2: 0.0, 3: 0.0},
          chordAccidentalOffsets: const {1: 0.0},
          chordDotOffsets: const {},
          noteAccidentals: const {1: 'flat'},
          chordGroups: const {
            (16000, true): [0, 1, 2],
            (17000, false): [3],
          },
          space: 10.0,
        );

        expect(res.noteXs.length, equals(4));
        // Chord notes at beat 16 all share the same base X
        final chordBaseX = res.noteXs[0]!;
        expect(res.noteXs[1], equals(chordBaseX));
        expect(res.noteXs[2], equals(chordBaseX));

        // The displaced notehead is at chordBaseX - 11.8
        final leftmostHeadX = chordBaseX - 11.8;
        // The accidental is at leftmostHeadX - 1.3 * space = chordBaseX - 24.8
        final accidentalX = leftmostHeadX - 13.0;

        // Accidental MUST sit comfortably to the right of the left barline (100.0) with at least 10px clearance
        expect(accidentalX, greaterThanOrEqualTo(100.0 + 10.0));

        // Next note at beat 17 is clearly separated from chord at beat 16
        final nextNoteX = res.noteXs[3]!;
        expect(nextNoteX - chordBaseX, greaterThan(35.0));

        // Anchors include measure boundaries
        expect(res.anchors.first.$1, equals(16.0));
        expect(res.anchors.first.$2, equals(100.0));
        expect(res.anchors.last.$1, equals(20.0));
        expect(res.anchors.last.$2, equals(300.0));
      });

      test('playhead glides continuously across the barline (no jump)', () {
        final notes = [
          for (var i = 0; i < 8; i++) StaffNote(60 + i, i * 1.0, 1.0),
        ];
        const config = ScorePageConfig(pageWidth: 800.0);
        final measures = ScorePageLayout.buildMeasures(
          notes: notes,
          beatsPerBar: 4.0,
          totalBeats: 8.0,
          space: config.space,
          minMeasureWidth: 100.0,
        );
        final sys = ScorePageLayout.breakSystems(
          measures: measures,
          config: config,
        ).first;
        double x(double b) =>
            sys.beatToX(b, config: config, keyFifths: 0, beatsPerBar: 4.0);
        final before = x(4.0 - 0.001);
        final after = x(4.0);
        expect((after - before).abs(), lessThan(1.0));
      });

      test('ScoreSystem beatToX and xToBeat invert accurately with notehead snapping', () {
        final notes = [
          const StaffNote(60, 0.0, 1.0), // C4 at beat 0
          const StaffNote(62, 1.0, 1.0), // D4 at beat 1
          const StaffNote(64, 2.0, 1.0), // E4 at beat 2
          const StaffNote(65, 3.0, 1.0), // F4 at beat 3
        ];
        const config = ScorePageConfig(
          pageWidth: 800.0,
          systemHeaderWidth: 70.0,
          space: 10.0,
        );
        final measures = ScorePageLayout.buildMeasures(
          notes: notes,
          beatsPerBar: 4.0,
          totalBeats: 4.0,
          space: config.space,
          minMeasureWidth: 100.0,
        );
        final systems = ScorePageLayout.breakSystems(
          measures: measures,
          config: config,
        );
        final sys = systems.first;

        final layout = sys.getLayout(
          config: config,
          keyFifths: 0,
          beatsPerBar: 4.0,
        );
        // Cached layout check
        expect(
          identical(
            sys.getLayout(config: config, keyFifths: 0, beatsPerBar: 4.0),
            layout,
          ),
          isTrue,
        );

        // Note 0 is at beat 0.0
        final note0X = layout.noteXs[0]!;
        expect(note0X, greaterThan(config.systemHeaderWidth));

        // Click exactly on Note 0
        final beatOnNote0 = sys.xToBeat(
          note0X,
          config: config,
          keyFifths: 0,
          beatsPerBar: 4.0,
        );
        expect(beatOnNote0, closeTo(0.0, 1e-4));

        // Click slightly to the right of Note 0 within snap radius (space * 0.75 = 7.5px)
        final beatSnappedRight = sys.xToBeat(
          note0X + 4.0,
          config: config,
          keyFifths: 0,
          beatsPerBar: 4.0,
        );
        expect(beatSnappedRight, closeTo(0.0, 1e-4));

        // Click slightly to the left of Note 0 within snap radius
        final beatSnappedLeft = sys.xToBeat(
          note0X - 4.0,
          config: config,
          keyFifths: 0,
          beatsPerBar: 4.0,
        );
        expect(beatSnappedLeft, closeTo(0.0, 1e-4));

        // beatToX at beat 0.0 lands exactly on Note 0
        final curX0 = sys.beatToX(
          0.0,
          config: config,
          keyFifths: 0,
          beatsPerBar: 4.0,
        );
        expect(curX0, closeTo(note0X, 1e-4));

        // Note 1 is at beat 1.0
        final note1X = layout.noteXs[1]!;
        final beatOnNote1 = sys.xToBeat(
          note1X,
          config: config,
          keyFifths: 0,
          beatsPerBar: 4.0,
        );
        expect(beatOnNote1, closeTo(1.0, 1e-4));
        final curX1 = sys.beatToX(
          1.0,
          config: config,
          keyFifths: 0,
          beatsPerBar: 4.0,
        );
        expect(curX1, closeTo(note1X, 1e-4));

        // Click midway between Note 0 and Note 1: mathematical inverse holds
        final midX = (note0X + note1X) / 2.0;
        final midBeat = sys.xToBeat(
          midX,
          config: config,
          keyFifths: 0,
          beatsPerBar: 4.0,
        );
        expect(midBeat, greaterThan(0.0));
        expect(midBeat, lessThan(1.0));
        final roundTripX = sys.beatToX(
          midBeat,
          config: config,
          keyFifths: 0,
          beatsPerBar: 4.0,
        );
        expect(roundTripX, closeTo(midX, 1e-4));

        // Click in system header area seeks to system start beat (0.0)
        final headerClickBeat = sys.xToBeat(
          20.0,
          config: config,
          keyFifths: 0,
          beatsPerBar: 4.0,
        );
        expect(headerClickBeat, equals(0.0));
      });
    },
  );
}
