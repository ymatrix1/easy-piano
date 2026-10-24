import 'dart:math' as math;

import 'key_signature.dart';
import 'segment_layout.dart';
import 'staff_note.dart';

/// Single layout measure within a multi-system score layout (MuseScore `Measure`).
class ScoreMeasure {
  const ScoreMeasure({
    required this.index,
    required this.startBeat,
    required this.endBeat,
    required this.notes,
    required this.minWidth,
  });

  /// 0-indexed measure ordinal in the score.
  final int index;

  /// Starting musical beat time of the measure.
  final double startBeat;

  /// Ending musical beat time of the measure.
  final double endBeat;

  /// List of notes/chords/rests that start within this measure.
  final List<StaffNote> notes;

  /// Minimum intrinsic width (in points/pixels) required to render without collisions.
  final double minWidth;
}

/// A horizontal system line containing one or more measures (MuseScore `System`).
class ScoreSystem {
  ScoreSystem({
    required this.systemIndex,
    required this.measures,
    required this.measureWidths,
    required this.measureXs,
    required this.totalWidth,
    required this.hasClefAndKey,
  });

  /// System line ordinal in the overall score.
  final int systemIndex;

  /// Measures assigned to this system.
  final List<ScoreMeasure> measures;

  /// Justified width assigned to each measure in this system.
  final List<double> measureWidths;

  /// X offset of each measure relative to system left edge (after system header).
  final List<double> measureXs;

  /// Width of the system content (matches printable width).
  final double totalWidth;

  /// Whether this system includes the leading clef, key signature, and brace.
  final bool hasClefAndKey;
}

/// A rendered page consisting of vertically stacked systems (MuseScore `Page`).
class ScorePage {
  const ScorePage({
    required this.pageIndex,
    required this.systems,
    required this.pageWidth,
    required this.pageHeight,
  });

  /// 0-indexed page number.
  final int pageIndex;

  /// Systems placed on this page.
  final List<ScoreSystem> systems;

  /// Overall page width (e.g. A4 / Letter width or canvas viewport width).
  final double pageWidth;

  /// Overall page height.
  final double pageHeight;
}

/// Configuration parameters for score engraving page layout.
class ScorePageConfig {
  const ScorePageConfig({
    this.pageWidth = 800.0,
    this.pageHeight = 1130.0,
    this.marginTop = 48.0,
    this.marginBottom = 48.0,
    this.marginLeft = 40.0,
    this.marginRight = 40.0,
    this.systemDistance = 64.0,
    this.grandStaffHeight = 110.0,
    this.systemHeaderWidth = 60.0,
    this.minMeasureWidth = 90.0,
    this.maxMeasuresPerSystem = 6,
    this.minMeasuresPerSystem = 2,
    this.space = 10.0,
  });

  final double pageWidth;
  final double pageHeight;
  final double marginTop;
  final double marginBottom;
  final double marginLeft;
  final double marginRight;

  /// Vertical space between successive grand staff systems.
  final double systemDistance;

  /// Approximate height of one grand staff (treble + bass + margin).
  final double grandStaffHeight;

  /// Width consumed at the start of a system for clefs, key sig, and bracket.
  final double systemHeaderWidth;

  /// Minimum width allowed for a measure.
  final double minMeasureWidth;

  /// Maximum measures allowed per line to prevent over-compression.
  final int maxMeasuresPerSystem;

  /// Minimum measures preferred per line when possible.
  final int minMeasuresPerSystem;

  /// Engraving space unit ($sp$).
  final double space;

  /// Printable horizontal width for measures.
  double get printableWidth =>
      math.max(100.0, pageWidth - marginLeft - marginRight);

  /// Printable horizontal width after subtracting the system clef/key header.
  double get systemMeasureWidth =>
      math.max(50.0, printableWidth - systemHeaderWidth);

  /// Printable vertical height for systems.
  double get printableHeight =>
      math.max(100.0, pageHeight - marginTop - marginBottom);
}

/// Algorithmic line breaking, system justification, and page distribution
/// matching MuseScore Studio's `pagelayout.cpp` and `scorepageviewlayout.cpp`.
abstract final class ScorePageLayout {
  /// Partitions notes into ordered `ScoreMeasure`s based on `beatsPerBar`.
  static List<ScoreMeasure> buildMeasures({
    required List<StaffNote> notes,
    required double beatsPerBar,
    required double totalBeats,
    double space = 10.0,
    double minMeasureWidth = 90.0,
    Map<int, AccidentalType> noteAccidentals = const {},
  }) {
    if (beatsPerBar <= 0) return const [];

    final numMeasures = math.max(1, (totalBeats / beatsPerBar).ceil());
    final measuresNotes = List.generate(
      numMeasures,
      (_) => <StaffNote>[],
      growable: false,
    );

    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      if (n.isSpacer) continue;
      final mIdx = (n.beat / beatsPerBar).floor();
      if (mIdx >= 0 && mIdx < numMeasures) {
        measuresNotes[mIdx].add(n);
      }
    }

    final measures = <ScoreMeasure>[];
    for (var m = 0; m < numMeasures; m++) {
      final start = m * beatsPerBar;
      final end = (m + 1) * beatsPerBar;
      final mNotes = measuresNotes[m];

      // Estimate minimum width using segment layout density
      double minW = minMeasureWidth;
      if (mNotes.isNotEmpty) {
        // Collect segments within this measure
        final segments = SegmentLayout.buildSegments(
          notes: mNotes,
          anchorX: 0.0,
          nowBeat: start,
          pixelsPerBeat: space * 3.0,
          space: space,
          beatsPerBar: beatsPerBar,
          noteAccidentals: noteAccidentals,
        );
        if (segments.length > 1) {
          final span = segments.last.scoreX - segments.first.scoreX;
          minW = math.max(minW, span + space * 4.0);
        } else {
          minW = math.max(minW, space * 6.0);
        }
      }

      measures.add(
        ScoreMeasure(
          index: m,
          startBeat: start,
          endBeat: end,
          notes: mNotes,
          minWidth: minW,
        ),
      );
    }

    return measures;
  }

  /// Groups measures into lines/systems using balanced line breaking
  /// and applies MuseScore proportional horizontal justification.
  static List<ScoreSystem> breakSystems({
    required List<ScoreMeasure> measures,
    required ScorePageConfig config,
  }) {
    if (measures.isEmpty) return const [];

    final targetWidth = config.systemMeasureWidth;
    final systems = <ScoreSystem>[];

    var startIdx = 0;
    var systemIndex = 0;

    while (startIdx < measures.length) {
      var currentWidth = 0.0;
      var count = 0;

      while (startIdx + count < measures.length) {
        final nextMeasure = measures[startIdx + count];
        final testWidth = currentWidth + nextMeasure.minWidth;

        // Check if adding this measure exceeds target width or max limit
        if (count >= config.minMeasuresPerSystem &&
            (testWidth > targetWidth || count >= config.maxMeasuresPerSystem)) {
          break;
        }

        currentWidth = testWidth;
        count++;

        if (count >= config.maxMeasuresPerSystem) {
          break;
        }
      }

      if (count == 0) count = 1;

      final sysMeasures = measures.sublist(startIdx, startIdx + count);
      final isLastSystem = (startIdx + count) >= measures.length;

      // System justification:
      // MuseScore HorizontalSpacing::justifyMeasures:
      // Proportional expansion: w_i = w_min_i + remaining * (w_min_i / sum_w_min)
      final sumMin = sysMeasures.fold<double>(
        0.0,
        (acc, m) => acc + m.minWidth,
      );
      final extra = math.max(0.0, targetWidth - sumMin);

      final measureWidths = <double>[];
      final measureXs = <double>[];
      var runningX = 0.0;

      for (var i = 0; i < sysMeasures.length; i++) {
        final m = sysMeasures[i];
        final double justifiedW;
        if (isLastSystem &&
            extra > targetWidth * 0.4 &&
            sysMeasures.length <= 2) {
          // On last unfinished system, avoid exaggerated stretching (MuseScore style)
          justifiedW = m.minWidth * 1.15;
        } else {
          final ratio = sumMin > 0 ? (m.minWidth / sumMin) : (1.0 / count);
          justifiedW = m.minWidth + extra * ratio;
        }
        measureWidths.add(justifiedW);
        measureXs.add(runningX);
        runningX += justifiedW;
      }

      systems.add(
        ScoreSystem(
          systemIndex: systemIndex++,
          measures: sysMeasures,
          measureWidths: measureWidths,
          measureXs: measureXs,
          totalWidth: config.printableWidth,
          hasClefAndKey: true,
        ),
      );

      startIdx += count;
    }

    return systems;
  }

  /// Organizes systems into pages according to printable vertical height.
  static List<ScorePage> paginate({
    required List<ScoreSystem> systems,
    required ScorePageConfig config,
  }) {
    if (systems.isEmpty) return const [];

    final systemTotalHeight = config.grandStaffHeight + config.systemDistance;
    final systemsPerPage = math.max(
      1,
      (config.printableHeight / systemTotalHeight).floor(),
    );

    final pages = <ScorePage>[];
    for (var i = 0; i < systems.length; i += systemsPerPage) {
      final end = math.min(i + systemsPerPage, systems.length);
      final pageSystems = systems.sublist(i, end);
      pages.add(
        ScorePage(
          pageIndex: pages.length,
          systems: pageSystems,
          pageWidth: config.pageWidth,
          pageHeight: config.pageHeight,
        ),
      );
    }

    return pages;
  }

  /// End-to-end convenience method: takes raw notes and config, produces pages.
  static List<ScorePage> layoutScore({
    required List<StaffNote> notes,
    required double beatsPerBar,
    required double totalBeats,
    ScorePageConfig config = const ScorePageConfig(),
    Map<int, AccidentalType> noteAccidentals = const {},
  }) {
    final measures = buildMeasures(
      notes: notes,
      beatsPerBar: beatsPerBar,
      totalBeats: totalBeats,
      space: config.space,
      minMeasureWidth: config.minMeasureWidth,
      noteAccidentals: noteAccidentals,
    );

    final systems = breakSystems(measures: measures, config: config);
    return paginate(systems: systems, config: config);
  }
}
