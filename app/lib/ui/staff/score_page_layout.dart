import 'dart:math' as math;

import 'staff_note.dart';
import 'staff_painter.dart';
import 'song_marks_parser.dart';

/// Single layout measure within a multi-system score layout (MuseScore `Measure`).
class ScoreMeasure {
  const ScoreMeasure({
    required this.index,
    required this.startBeat,
    required this.endBeat,
    required this.notes,
    required this.minWidth,
    this.numerator = 4,
    this.denominator = 4,
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
  final int numerator;
  final int denominator;
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

  /// Cached layout geometry for note rendering and cursor mapping.
  SystemLayoutResult? cachedLayout;

  /// First musical beat included in this system.
  double get startBeat => measures.isEmpty ? 0.0 : measures.first.startBeat;

  /// Last musical beat included in this system.
  double get endBeat => measures.isEmpty ? 0.0 : measures.last.endBeat;

  /// Obtains the computed system layout result, using the cached result if available.
  SystemLayoutResult getLayout({
    required ScorePageConfig config,
    required int keyFifths,
    required double beatsPerBar,
  }) {
    if (cachedLayout != null) return cachedLayout!;
    final layout = ScorePageLayout.layoutSystem(
      system: this,
      config: config,
      keyFifths: keyFifths,
      beatsPerBar: beatsPerBar,
    );
    cachedLayout = layout;
    return layout;
  }

  /// Maps a musical beat to horizontal X coordinate on this system.
  double beatToX(
    double beat, {
    required ScorePageConfig config,
    required int keyFifths,
    required double beatsPerBar,
  }) {
    return getLayout(
      config: config,
      keyFifths: keyFifths,
      beatsPerBar: beatsPerBar,
    ).beatToX(beat, this, config);
  }

  /// Maps horizontal X coordinate on this system to musical beat.
  double xToBeat(
    double x, {
    required ScorePageConfig config,
    required int keyFifths,
    required double beatsPerBar,
  }) {
    return getLayout(
      config: config,
      keyFifths: keyFifths,
      beatsPerBar: beatsPerBar,
    ).xToBeat(x, this, config);
  }
}

/// Cached layout geometry for an engraved score system line.
///
/// Precomputes non-linear notehead positions, accidental staggering, dot
/// offsets, stem directions, and piecewise interpolation anchors between beats
/// and canvas X coordinates (MuseScore `measurelayout.cpp`).
class SystemLayoutResult {
  const SystemLayoutResult({
    required this.allNotes,
    required this.noteXs,
    required this.measureAnchors,
    required this.chordGroups,
    required this.chordHeadOffsets,
    required this.chordStemDown,
    required this.chordAccidentalOffsets,
    required this.chordDotOffsets,
    required this.noteAccidentals,
  });

  /// All notes/rests across measures in this system.
  final List<StaffNote> allNotes;

  /// Map from system note index to nominal horizontal X position.
  final Map<int, double> noteXs;

  /// Measure index to list of (beat, x) interpolation anchors.
  final Map<int, List<(double beat, double x)>> measureAnchors;

  /// Chord groups key: (beatInt, onBass), value: list of system note indices.
  final Map<(int, bool), List<int>> chordGroups;

  /// Notehead horizontal displacement offsets.
  final Map<int, double> chordHeadOffsets;

  /// Stem direction for chord groups.
  final Map<(int, bool), bool> chordStemDown;

  /// Accidental horizontal staggering offsets.
  final Map<int, double> chordAccidentalOffsets;

  /// Augmentation dot offsets.
  final Map<int, (double, double)> chordDotOffsets;

  /// Computed accidentals per note.
  final Map<int, AccidentalType> noteAccidentals;

  /// Maps a musical beat to its exact horizontal pixel coordinate on the system.
  double beatToX(double b, ScoreSystem system, ScorePageConfig config) {
    final headerW = config.systemHeaderWidth;
    if (system.measures.isEmpty) return headerW;

    for (var mIdx = 0; mIdx < system.measures.length; mIdx++) {
      final m = system.measures[mIdx];
      final isLast = mIdx == system.measures.length - 1;
      if (b >= m.startBeat &&
          (b < m.endBeat || (isLast && b <= m.endBeat + 0.001))) {
        final anchors = measureAnchors[mIdx];
        if (anchors == null || anchors.isEmpty) {
          final mLeft = headerW + system.measureXs[mIdx];
          final mW = system.measureWidths[mIdx];
          final rel =
              (b - m.startBeat) / math.max(0.001, m.endBeat - m.startBeat);
          return mLeft + rel * mW;
        }

        // If at or before first anchor, return the notehead position if there's a note on that beat
        if (b <= anchors.first.$1) {
          if (anchors.length > 1 &&
              (anchors[1].$1 - anchors.first.$1).abs() <= 1e-4) {
            return anchors[1].$2;
          }
          return anchors.first.$2;
        }

        if (b >= anchors.last.$1) return anchors.last.$2;

        for (var a = 0; a < anchors.length - 1; a++) {
          final a0 = anchors[a];
          final a1 = anchors[a + 1];
          if (b >= a0.$1 && b <= a1.$1) {
            final span = a1.$1 - a0.$1;
            if (span <= 1e-4) {
              // Duplicate beat anchor (e.g. barline anchor followed by first notehead anchor)
              continue;
            }
            final t = (b - a0.$1) / span;
            return a0.$2 + t * (a1.$2 - a0.$2);
          }
        }
        return anchors.last.$2;
      }
    }
    if (b < system.startBeat) {
      return headerW;
    }
    return headerW + (system.measureXs.last + system.measureWidths.last);
  }

  /// Maps a horizontal pixel coordinate on the system to musical beat.
  /// This is the mathematical inverse of [beatToX], with notehead snapping.
  double xToBeat(double x, ScoreSystem system, ScorePageConfig config) {
    final headerW = config.systemHeaderWidth;
    if (system.measures.isEmpty || x <= headerW) {
      return system.startBeat;
    }

    final systemEnd =
        headerW +
        (system.measureXs.isNotEmpty
            ? (system.measureXs.last + system.measureWidths.last)
            : 0.0);
    if (x >= systemEnd) {
      return system.endBeat;
    }

    // Snap to notehead if click is within snap threshold (space * 0.75)
    final snapRadius = config.space * 0.75;
    var closestDist = double.infinity;
    double? snappedBeat;

    for (var i = 0; i < allNotes.length; i++) {
      final n = allNotes[i];
      if (n.isRest || n.isSpacer) continue;
      final rawX = noteXs[i] ?? 0.0;
      final headX = rawX + (chordHeadOffsets[i] ?? 0.0);
      final dist = (x - headX).abs();
      if (dist <= snapRadius && dist < closestDist) {
        closestDist = dist;
        snappedBeat = n.beat;
      }
    }
    if (snappedBeat != null) {
      return snappedBeat;
    }

    // Piecewise inverse interpolation using measureAnchors
    for (var mIdx = 0; mIdx < system.measures.length; mIdx++) {
      final m = system.measures[mIdx];
      final mLeft = headerW + system.measureXs[mIdx];
      final mW = system.measureWidths[mIdx];
      final mRight = mLeft + mW;
      final isLast = mIdx == system.measures.length - 1;

      if (x >= mLeft && (x <= mRight || isLast)) {
        final anchors = measureAnchors[mIdx];
        if (anchors == null || anchors.isEmpty) {
          final frac = mW > 0 ? ((x - mLeft) / mW).clamp(0.0, 1.0) : 0.0;
          return m.startBeat + frac * (m.endBeat - m.startBeat);
        }
        if (x <= anchors.first.$2) return anchors.first.$1;
        if (x >= anchors.last.$2) return anchors.last.$1;

        for (var a = 0; a < anchors.length - 1; a++) {
          final a0 = anchors[a];
          final a1 = anchors[a + 1];
          final minX = math.min(a0.$2, a1.$2);
          final maxX = math.max(a0.$2, a1.$2);
          if (x >= minX && x <= maxX) {
            final xSpan = a1.$2 - a0.$2;
            final t = xSpan.abs() > 1e-4 ? (x - a0.$2) / xSpan : 0.0;
            return a0.$1 + t * (a1.$1 - a0.$1);
          }
        }
        return anchors.last.$1;
      }
    }

    return system.endBeat;
  }
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
    List<double> measureStarts = const [],
    List<StaffSignatureChange> signatureChanges = const [],
    int baseDenominator = 4,
  }) {
    if (beatsPerBar <= 0) return const [];

    final starts = measureStarts.isEmpty
        ? List<double>.generate(
            (totalBeats / beatsPerBar).ceil() + 1,
            (i) => i * beatsPerBar,
          )
        : measureStarts;
    final numMeasures = math.max(1, starts.length - 1);
    final measuresNotes = List.generate(
      numMeasures,
      (_) => <StaffNote>[],
      growable: false,
    );

    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      if (n.isSpacer) continue;
      final mIdx = measureStarts.isEmpty
          ? (n.beat / beatsPerBar).floor()
          : math.max(
              0,
              measureStarts.lastIndexWhere((beat) => beat <= n.beat + 1e-6),
            );
      if (mIdx >= 0 && mIdx < numMeasures) {
        measuresNotes[mIdx].add(n);
      }
    }

    final measures = <ScoreMeasure>[];
    for (var m = 0; m < numMeasures; m++) {
      final start = starts[m];
      final end = starts[m + 1];
      final change = signatureChanges
          .where((c) => c.beat <= start + 1e-6)
          .lastOrNull;
      final mNotes = measuresNotes[m];
      final measureBpb = end - start;

      // Estimate minimum width using segment layout density
      double minW = minMeasureWidth;
      if (mNotes.isNotEmpty) {
        final mAccidentals = noteAccidentals.isNotEmpty
            ? noteAccidentals
            : StaffPainter.computeAccidentals(
                notes: mNotes,
                keyFifths: keyFifths,
                beatsPerBar: measureBpb,
                measureStarts: [start],
                signatureChanges: signatureChanges,
                onBass: (n) => n.leftHand,
              );
        final segments = SegmentLayout.buildSegments(
          notes: mNotes,
          anchorX: 0.0,
          nowBeat: start,
          pixelsPerBeat: space * 3.0,
          space: space,
          beatsPerBar: measureBpb,
          measureStarts: [start],
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
          numerator: change?.numerator ?? beatsPerBar.round(),
          denominator: change?.denominator ?? baseDenominator,
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
    List<double> measureStarts = const [],
    List<StaffSignatureChange> signatureChanges = const [],
    int baseDenominator = 4,
  }) {
    final measures = buildMeasures(
      notes: notes,
      beatsPerBar: beatsPerBar,
      totalBeats: totalBeats,
      space: config.space,
      minMeasureWidth: config.minMeasureWidth,
      noteAccidentals: noteAccidentals,
      measureStarts: measureStarts,
      signatureChanges: signatureChanges,
      baseDenominator: baseDenominator,
    );

    final systems = breakSystems(measures: measures, config: config);
    return paginate(systems: systems, config: config);
  }

  static final _trebleBottomStep = diatonicStep(64); // E4 = 30
  static final _bassTopStep = diatonicStep(57); // A3 = 26

  /// Width reserved at the start of each system for clef, key signature and
  /// time signature plus a trailing gap, so the first notes/chords never sit
  /// on top of the time signature (MuseScore lays the header out first and
  /// only then spaces the first segment).
  static double systemHeaderWidthFor({
    required int keyFifths,
    required double space,
  }) =>
      space * (0.4 + 3.4 + 2.0 + 1.5) +
      KeySignatureLayout.width(keyFifths, space);

  /// Calculates vertical baseline Y coordinate for a given pitch on grand staff.
  static double noteY(
    int pitch,
    bool onBass,
    double space,
    double trebleBottomY,
    double bassTopY,
  ) {
    final step = diatonicStep(pitch);
    final half = space / 2;
    return onBass
        ? bassTopY + (_bassTopStep - step) * half
        : trebleBottomY - (step - _trebleBottomStep) * half;
  }

  /// Performs full system-level layout: gathers all notes across measures,
  /// computes accidentals, chord grouping, notehead displacements, accidental
  /// and dot offsets, and non-linear measure spacing anchors.
  static SystemLayoutResult layoutSystem({
    required ScoreSystem system,
    required ScorePageConfig config,
    required int keyFifths,
    required double beatsPerBar,
  }) {
    final space = config.space;
    final headerW = config.systemHeaderWidth;
    final trebleBottomY = space * 5.0;
    final bassTopY = trebleBottomY + 3.0 * space;

    // Flatten all notes in system and track measure note indices
    final allSysNotes = <StaffNote>[];
    final measureNoteIndices = <int, List<int>>{};

    for (var mIdx = 0; mIdx < system.measures.length; mIdx++) {
      final m = system.measures[mIdx];
      measureNoteIndices[mIdx] = [];
      for (final note in m.notes) {
        if (note.isSpacer) continue;
        final globalIdx = allSysNotes.length;
        allSysNotes.add(note);
        measureNoteIndices[mIdx]!.add(globalIdx);
      }
    }

    // Accidentals computation matching Mode 1 StaffPainter
    final noteAccidentals = StaffPainter.computeAccidentals(
      notes: allSysNotes,
      keyFifths: keyFifths,
      beatsPerBar: beatsPerBar,
      onBass: (n) => n.leftHand,
    );

    // Chord grouping & displacements (MuseScore chordlayout.cpp & Gould rules)
    final chordGroups = <(int, bool), List<int>>{};
    for (var i = 0; i < allSysNotes.length; i++) {
      final n = allSysNotes[i];
      if (n.isRest || n.isSpacer) continue;
      final beatInt = (n.beat * 1000).round();
      chordGroups.putIfAbsent((beatInt, n.leftHand), () => []).add(i);
    }

    final chordHeadOffsets = <int, double>{};
    final chordStemDown = <(int, bool), bool>{};

    for (final entry in chordGroups.entries) {
      final group = entry.value;
      final onBass = entry.key.$2;
      final chordPitches = group.map((idx) => allSysNotes[idx].pitch).toList();
      final isDown = StemLayout.computeStemDown(
        pitch: chordPitches.first,
        onBass: onBass,
        explicitStemDown: allSysNotes[group.first].stemDown,
        chordPitches: chordPitches,
      );
      chordStemDown[entry.key] = isDown;

      final offsets = ChordLayout.computeNoteheadOffsets(
        notes: allSysNotes,
        chordIndices: group,
        stemDown: isDown,
        space: space,
      );
      chordHeadOffsets.addAll(offsets);
    }

    // MuseScore parity: accidental staggering and dot conflict resolution for chords
    final chordAccidentalOffsets = <int, double>{};
    final chordDotOffsets = <int, (double, double)>{};
    for (final entry in chordGroups.entries) {
      final group = entry.value;
      final onB = entry.key.$2;

      final accOffsets = ChordLayout.computeAccidentalOffsets(
        notes: allSysNotes,
        chordIndices: group,
        noteAccidentals: noteAccidentals,
        noteY: (pitch, onBass) =>
            noteY(pitch, onBass, space, trebleBottomY, bassTopY),
        onBass: onB,
        space: space,
      );
      chordAccidentalOffsets.addAll(accOffsets);

      final dotOffsets = ChordLayout.computeDotOffsets(
        notes: allSysNotes,
        chordIndices: group,
        chordHeadOffsets: chordHeadOffsets,
        space: space,
      );
      chordDotOffsets.addAll(dotOffsets);
    }

    // Horizontal spacing per measure & playhead anchors
    final noteXsMap = <int, double>{};
    final measureAnchors = <int, List<(double, double)>>{};

    for (var mIdx = 0; mIdx < system.measures.length; mIdx++) {
      final m = system.measures[mIdx];
      final mLeft = headerW + system.measureXs[mIdx];
      final mW = system.measureWidths[mIdx];
      final indices = measureNoteIndices[mIdx] ?? const [];

      final layoutRes = layoutMeasureNotes(
        allNotes: allSysNotes,
        measureNoteIndices: indices,
        measureStartBeat: m.startBeat,
        measureEndBeat: m.endBeat,
        measureLeft: mLeft,
        measureWidth: mW,
        chordHeadOffsets: chordHeadOffsets,
        chordAccidentalOffsets: chordAccidentalOffsets,
        chordDotOffsets: chordDotOffsets,
        noteAccidentals: noteAccidentals,
        chordGroups: chordGroups,
        space: space,
      );

      noteXsMap.addAll(layoutRes.noteXs);
      measureAnchors[mIdx] = layoutRes.anchors;
    }

    // Continuous playhead across barlines: the last segment of a measure
    // glides to the first notehead of the next measure instead of stopping at
    // the barline (which made the cursor jump by the leading padding).
    for (var mIdx = 0; mIdx < system.measures.length - 1; mIdx++) {
      final cur = measureAnchors[mIdx];
      final next = measureAnchors[mIdx + 1];
      if (cur == null || next == null || cur.length < 2 || next.length < 2) {
        continue;
      }
      final nextFirstX = next.length > 2 ? next[1].$2 : next.first.$2;
      if (nextFirstX > cur.last.$2) {
        cur[cur.length - 1] = (cur.last.$1, nextFirstX);
      }
    }

    return SystemLayoutResult(
      allNotes: allSysNotes,
      noteXs: noteXsMap,
      measureAnchors: measureAnchors,
      chordGroups: chordGroups,
      chordHeadOffsets: chordHeadOffsets,
      chordStemDown: chordStemDown,
      chordAccidentalOffsets: chordAccidentalOffsets,
      chordDotOffsets: chordDotOffsets,
      noteAccidentals: noteAccidentals,
    );
  }
}
