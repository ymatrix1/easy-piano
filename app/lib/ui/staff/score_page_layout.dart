import 'dart:math' as math;

import 'staff_note.dart';
import 'staff_painter.dart';

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
    this.isLastSystem = false,
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

  /// Whether this is the final system in the score (for end barline rendering).
  final bool isLastSystem;

  /// First musical beat included in this system.
  double get startBeat => measures.isEmpty ? 0.0 : measures.first.startBeat;

  /// Last musical beat included in this system.
  double get endBeat => measures.isEmpty ? 0.0 : measures.last.endBeat;
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

  /// First musical beat on this page.
  double get startBeat => systems.isEmpty ? 0.0 : systems.first.startBeat;

  /// Last musical beat on this page.
  double get endBeat => systems.isEmpty ? 0.0 : systems.last.endBeat;
}

/// Configuration parameters for score engraving page layout.
class ScorePageConfig {
  const ScorePageConfig({
    this.pageWidth = 840.0,
    this.pageHeight = 1150.0,
    this.marginTop = 48.0,
    this.marginBottom = 48.0,
    this.marginLeft = 40.0,
    this.marginRight = 40.0,
    this.systemDistance = 64.0,
    this.grandStaffHeight = 135.0,
    this.systemHeaderWidth = 64.0,
    this.minMeasureWidth = 110.0,
    this.maxMeasuresPerSystem = 4,
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
    int keyFifths = 0,
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
        final mAccidentals = noteAccidentals.isNotEmpty
            ? noteAccidentals
            : StaffPainter.computeAccidentals(
                notes: mNotes,
                keyFifths: keyFifths,
                beatsPerBar: beatsPerBar,
                onBass: (n) => n.leftHand,
              );
        final segments = SegmentLayout.buildSegments(
          notes: mNotes,
          anchorX: 0.0,
          nowBeat: start,
          pixelsPerBeat: space * 3.0,
          space: space,
          beatsPerBar: beatsPerBar,
          noteAccidentals: mAccidentals,
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

  /// Computes non-linear, collision-free horizontal coordinates for all notes
  /// in a measure, plus measure beat anchors for tranquil playhead movement
  /// (MuseScore `measurelayout.cpp` & `horizontalspacing.cpp`).
  static ({Map<int, double> noteXs, List<(double beat, double x)> anchors})
  layoutMeasureNotes({
    required List<StaffNote> allNotes,
    required List<int> measureNoteIndices,
    required double measureStartBeat,
    required double measureEndBeat,
    required double measureLeft,
    required double measureWidth,
    required Map<int, double> chordHeadOffsets,
    required Map<int, double> chordAccidentalOffsets,
    required Map<int, (double, double)> chordDotOffsets,
    required Map<int, dynamic> noteAccidentals,
    required Map<(int, bool), List<int>> chordGroups,
    required double space,
  }) {
    final noteXs = <int, double>{};
    if (measureNoteIndices.isEmpty) {
      return (
        noteXs: noteXs,
        anchors: [
          (measureStartBeat, measureLeft),
          (measureEndBeat, measureLeft + measureWidth),
        ],
      );
    }

    // Group notes in this measure by unique beat (rounded to 1e-4)
    final beatGroups = <double, List<int>>{};
    for (final idx in measureNoteIndices) {
      final b = (allNotes[idx].beat * 10000).round() / 10000;
      beatGroups.putIfAbsent(b, () => []).add(idx);
    }
    final sortedBeats = beatGroups.keys.toList()..sort();

    // Calculate required clearance to the left and right of nominal X for each beat
    final leftClearances = <double>[];
    final rightClearances = <double>[];

    for (final b in sortedBeats) {
      final bIndices = beatGroups[b]!;
      final clearances = ChordLayout.computeBeatClearances(
        notes: allNotes,
        noteIndices: bIndices,
        chordHeadOffsets: chordHeadOffsets,
        chordAccidentalOffsets: chordAccidentalOffsets,
        chordDotOffsets: chordDotOffsets,
        noteAccidentals: noteAccidentals,
        chordGroups: chordGroups,
        space: space,
      );
      leftClearances.add(clearances.leftClearance);
      rightClearances.add(clearances.rightClearance);
    }

    // Clearance from left barline to first beat, and last beat to right barline
    final leftPad = math.max(space * 1.6, leftClearances.first + space * 1.0);
    final rightPad = math.max(space * 1.2, rightClearances.last + space * 0.8);

    // Spacing between consecutive beats
    final xRels = <double>[0.0];
    for (var k = 0; k < sortedBeats.length - 1; k++) {
      final deltaBeats = sortedBeats[k + 1] - sortedBeats[k];
      final minInkDist =
          rightClearances[k] + space * 0.5 + leftClearances[k + 1];
      final nominalDist =
          SegmentLayout.durationStretch(deltaBeats) * space * 3.5;
      final spacing = math.max(minInkDist, nominalDist);
      xRels.add(xRels[k] + spacing);
    }

    final totalSpan = xRels.last;
    final usableW = math.max(totalSpan, measureWidth - leftPad - rightPad);
    final scale = totalSpan > 0 ? (usableW / totalSpan) : 1.0;

    final anchors = <(double, double)>[];
    anchors.add((measureStartBeat, measureLeft));

    for (var k = 0; k < sortedBeats.length; k++) {
      final b = sortedBeats[k];
      final beatX = measureLeft + leftPad + xRels[k] * scale;
      anchors.add((b, beatX));
      for (final idx in beatGroups[b]!) {
        noteXs[idx] = beatX;
      }
    }

    anchors.add((measureEndBeat, measureLeft + measureWidth));

    return (noteXs: noteXs, anchors: anchors);
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

    // Determine balanced measure counts per system (MuseScore style)
    final systemCounts = _calculateBalancedSystemCounts(
      measures: measures,
      targetWidth: targetWidth,
      maxPerSystem: config.maxMeasuresPerSystem,
      minPerSystem: config.minMeasuresPerSystem,
    );

    var startIdx = 0;
    for (var sysIdx = 0; sysIdx < systemCounts.length; sysIdx++) {
      final count = systemCounts[sysIdx];
      final sysMeasures = measures.sublist(startIdx, startIdx + count);
      final isLastSystem = (startIdx + count) >= measures.length;

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
        // Standard MuseScore system justification:
        // Every system spans the full width of the printable system area,
        // distributing space proportionally across all measures in the system.
        final ratio = sumMin > 0 ? (m.minWidth / sumMin) : (1.0 / count);
        final justifiedW = m.minWidth + extra * ratio;
        measureWidths.add(justifiedW);
        measureXs.add(runningX);
        runningX += justifiedW;
      }

      systems.add(
        ScoreSystem(
          systemIndex: sysIdx,
          measures: sysMeasures,
          measureWidths: measureWidths,
          measureXs: measureXs,
          totalWidth: config.printableWidth,
          hasClefAndKey: true,
          isLastSystem: isLastSystem,
        ),
      );

      startIdx += count;
    }

    return systems;
  }

  static List<int> _calculateBalancedSystemCounts({
    required List<ScoreMeasure> measures,
    required double targetWidth,
    required int maxPerSystem,
    required int minPerSystem,
  }) {
    final n = measures.length;
    if (n == 0) return const [];
    if (n <= 3) {
      final sum = measures.fold<double>(0.0, (acc, m) => acc + m.minWidth);
      if (sum <= targetWidth) return [n];
    }

    // Try finding the smallest number of systems s where all systems fit
    var s = math.max(2, (n / maxPerSystem).ceil());
    while (s <= n) {
      final q = n ~/ s;
      final r = n % s;
      final candidateCounts = List.generate(s, (i) => i < r ? q + 1 : q);

      var fits = true;
      var idx = 0;
      for (final c in candidateCounts) {
        if (c > maxPerSystem) {
          fits = false;
          break;
        }
        final sum = measures
            .sublist(idx, idx + c)
            .fold<double>(0.0, (acc, m) => acc + m.minWidth);
        if (sum > targetWidth) {
          fits = false;
          break;
        }
        idx += c;
      }

      if (fits) return candidateCounts;
      s++;
    }

    // Fallback: greedy packing
    final fallbackCounts = <int>[];
    var start = 0;
    while (start < n) {
      var currentW = 0.0;
      var count = 0;
      while (start + count < n) {
        final m = measures[start + count];
        if (count >= minPerSystem &&
            (currentW + m.minWidth > targetWidth || count >= maxPerSystem)) {
          break;
        }
        currentW += m.minWidth;
        count++;
        if (count >= maxPerSystem) break;
      }
      if (count == 0) count = 1;
      fallbackCounts.add(count);
      start += count;
    }
    return fallbackCounts;
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
