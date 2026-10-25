import 'package:flutter/material.dart';

/// Repeat barline at a bar line: `|:` ([start]), `:|` ([end]) or both (`:|:`).
///
/// [beat] is the bar line, same timeline as [StaffNote.beat].
class StaffRepeatBarline {
  const StaffRepeatBarline(this.beat, {this.start = false, this.end = false});

  final double beat;

  /// A repeat opens at this bar line (`{repeat_start}`).
  final bool start;

  /// A repeat closes at this bar line (`{repeat_end}`).
  final bool end;
}

/// A first or second ending (`{volta: [1]}`, `{volta: [2]}`) from the bar
/// line [startBeat] to the bar line [endBeat].
class StaffVolta {
  const StaffVolta({
    required this.startBeat,
    required this.endBeat,
    required this.number,
    this.closedEnd = false,
  });

  final double startBeat;
  final double endBeat;

  /// 1 or 2: the label is `1.` or `2.`.
  final int number;

  /// The right end has a down hook. True when the ending closes with a repeat
  /// sign (`{repeat_end}`), false when it closes with a plain bar line or the
  /// end of the song.
  final bool closedEnd;
}

/// Navigation mark kinds (`{segno}`, `{coda}`, `{dc_al_fine}`, `{ds_al_coda}`).
enum NavigationKind { segno, coda, dcAlFine, dsAlCoda }

/// A navigation mark above the staff at [beat].
class StaffNavigation {
  const StaffNavigation(this.beat, this.kind);

  final double beat;
  final NavigationKind kind;
}

/// Horizontal ink of one repeat barline group, in screen x.
class RepeatBarlineGeometry {
  const RepeatBarlineGeometry({
    required this.thinX,
    required this.thickX,
    required this.dotsX,
    required this.thinWidth,
    required this.thickWidth,
    required this.left,
    required this.right,
  });

  /// Centre x of each thin line.
  final List<double> thinX;

  /// Centre x of each thick line.
  final List<double> thickX;

  /// Left edge of each dot pair (origin of the `repeatDots` glyph).
  final List<double> dotsX;

  final double thinWidth;
  final double thickWidth;

  /// Outermost ink on the left (thick line or dots) and on the right.
  final double left;
  final double right;
}

/// Hook and line of one volta, in screen coordinates (y grows downwards).
class VoltaGeometry {
  const VoltaGeometry({
    required this.startX,
    required this.endX,
    required this.lineY,
    required this.hookBottomY,
    required this.closedEnd,
    required this.labelOrigin,
  });

  final double startX;
  final double endX;

  /// Y of the horizontal line.
  final double lineY;

  /// Bottom of the down hooks (left, and right when [closedEnd]).
  final double hookBottomY;
  final bool closedEnd;

  /// Baseline-left point of the `1.` / `2.` label.
  final Offset labelOrigin;
}

/// Repeat barlines, voltas and navigation marks. Pure functions, no painting
/// state.
///
/// Follows MuseScore `rendering/score/tdraw.cpp` (`TDraw::draw(BarLine)`:
/// `START_REPEAT`, `END_REPEAT`, `END_START_REPEAT` line and dot order, and
/// `drawDots`), `data/styles/legacy-style-defaults-v450.mss` (barWidth 0.18,
/// endBarWidth 0.55, endBarDistance 0.37, repeatBarlineDotSeparation 0.37,
/// voltaPosAbove y=-3, voltaHook 2.2, voltaLineWidth 0.11,
/// markerPosAbove y=-2) and `dom/volta.cpp` (hook at each end, closed right
/// hook only when the ending closes with a repeat).
///
/// Glyph codepoints are SMuFL names from `fonts/smufl/glyphnames.json`, checked
/// against `app/assets/fonts/Leland.otf`. Leland has no `repeatLeft` (U+E040),
/// `repeatRight` (U+E041), `dalSegno` (U+E045) or `daCapo` (U+E046), so the bar
/// lines are drawn as lines and the D.C./D.S. marks as text.
abstract final class RepeatLayout {
  /// `repeatDot` (U+E044): one dot, bbox x 0..0.416 sp, y -0.212..0.212 sp
  /// around the baseline, so the baseline is the dot centre
  /// (`leland_metadata.json`). MuseScore draws each repeat dot with this glyph
  /// (`tdraw.cpp` `drawDots`).
  static const repeatDotGlyph = '\uE044';

  /// `repeatDots` (U+E043): both dots in one glyph (not used by the painter,
  /// listed for reference). Its bbox is y 1.288..2.712 sp above the baseline.
  static const repeatDotsGlyph = '\uE043';

  /// `segno` (U+E047) and `coda` (U+E048): present in Leland.
  static const segnoGlyph = '\uE047';
  static const codaGlyph = '\uE048';

  /// Text labels for the jump marks (no Leland glyph for them).
  static const dcAlFineLabel = 'D.C. al Fine';
  static const dsAlCodaLabel = 'D.S. al Coda';

  /// Thin barline width (`barWidth`), in staff spaces.
  static const thinWidthSp = 0.18;

  /// Thick barline width (`endBarWidth`).
  static const thickWidthSp = 0.55;

  /// Gap between the thin and the thick line (`endBarDistance`).
  static const thickGapSp = 0.37;

  /// Gap between the thin line and the dots (`repeatBarlineDotSeparation`).
  static const dotSeparationSp = 0.37;

  /// Advance width of the `repeatDots` glyph (bbox NE x).
  static const dotsWidthSp = 0.416;

  /// Dot centres above the bottom staff line: spaces 2 and 3.
  static const dotLowerSp = 1.5;
  static const dotUpperSp = 2.5;

  /// Volta line height above the top staff line (`voltaPosAbove` y=-3).
  static const voltaLineSp = 3.0;

  /// Length of the volta's down hooks (`voltaHook`).
  static const voltaHookSp = 2.2;

  /// Volta line thickness (`voltaLineWidth`).
  static const voltaLineWidthSp = 0.11;

  /// Label inset from the volta's left end, and label baseline above the line.
  static const voltaLabelInsetSp = 0.5;
  static const voltaLabelRaiseSp = 0.45;

  /// Gap between a volta end and the repeat barline it meets.
  static const voltaRepeatGapSp = 0.2;

  /// Navigation mark baseline above the top staff line (`markerPosAbove`
  /// y=-2), and the higher baseline used when the mark sits under a volta.
  static const navigationBaselineSp = 2.0;
  static const navigationOverVoltaSp = 4.6;

  /// Geometry of one repeat barline group centred on [x], the bar line
  /// position the spacing picked for a plain bar line. Start (`|:`): thick,
  /// thin, dots. End (`:|`): dots, thin, thick. Both (`:|:`): dots, thin,
  /// thick, thin, dots. Offsets follow `TDraw::draw(BarLine)`: the group
  /// starts at x 0 and the thin/thick lines and dots are placed from there.
  /// No horizontal spacing is added for the group: a repeat sign in a tight
  /// gap can touch the notes next to it (see sheet-engraving.md).
  static RepeatBarlineGeometry barlineGeometry({
    required bool start,
    required bool end,
    required double x,
    required double space,
  }) {
    final thin = thinWidthSp * space;
    final thick = thickWidthSp * space;
    final gap = thickGapSp * space;
    final sep = dotSeparationSp * space;
    final dotW = dotsWidthSp * space;

    // Build left to right from the origin, then shift onto [x].
    final thinX = <double>[];
    final thickX = <double>[];
    final dotsX = <double>[];
    double left;
    double right;
    if (start && !end) {
      thickX.add(thick / 2);
      thinX.add(thickX.last + thick / 2 + gap + thin / 2);
      dotsX.add(thinX.last + thin / 2 + sep);
      left = 0;
      right = dotsX.last + dotW;
    } else if (end && !start) {
      dotsX.add(0);
      thinX.add(dotW + sep + thin / 2);
      thickX.add(thinX.last + thin / 2 + gap + thick / 2);
      left = 0;
      right = thickX.last + thick / 2;
    } else if (start && end) {
      dotsX.add(0);
      thinX.add(dotW + sep + thin / 2);
      thickX.add(thinX.last + thin / 2 + gap + thick / 2);
      thinX.add(thickX.last + thick / 2 + gap + thin / 2);
      dotsX.add(thinX.last + thin / 2 + sep);
      left = 0;
      right = dotsX.last + dotW;
    } else {
      return RepeatBarlineGeometry(
        thinX: const [],
        thickX: const [],
        dotsX: const [],
        thinWidth: thin,
        thickWidth: thick,
        left: x,
        right: x,
      );
    }

    // Centre the group's ink on [x], the bar line position that the spacing
    // (SegmentLayout.barLineX) chose for a plain bar line.
    final shift = x - right / 2;
    return RepeatBarlineGeometry(
      thinX: [for (final v in thinX) v + shift],
      thickX: [for (final v in thickX) v + shift],
      dotsX: [for (final v in dotsX) v + shift],
      thinWidth: thin,
      thickWidth: thick,
      left: left + shift,
      right: right + shift,
    );
  }

  /// Centre y of the two repeat dots of one staff, given its bottom line
  /// (spaces 2 and 3, upper first). Screen y grows downwards, so the dots sit
  /// above the bottom line. Each dot is a `repeatDot` glyph whose baseline is
  /// its centre.
  static List<double> dotCentresY({
    required double bottomLineY,
    required double space,
  }) => [bottomLineY - dotUpperSp * space, bottomLineY - dotLowerSp * space];

  /// x of a volta's left end. A volta that starts where a repeat sign is
  /// drawn begins after that sign's ink; otherwise it starts at the bar line.
  static double voltaStartX({
    required double barX,
    required RepeatBarlineGeometry? group,
    required double space,
  }) => group == null ? barX : group.right + voltaRepeatGapSp * space;

  /// x of a volta's right end. A volta that ends where a repeat sign is drawn
  /// stops before that sign's ink; otherwise it ends at the bar line.
  static double voltaEndX({
    required double barX,
    required RepeatBarlineGeometry? group,
    required double space,
  }) => group == null ? barX : group.left - voltaRepeatGapSp * space;

  /// Volta line, hooks and label for a volta from [startX] to [endX], above a
  /// staff whose top line is [staffTopY].
  static VoltaGeometry voltaGeometry({
    required double startX,
    required double endX,
    required double staffTopY,
    required double space,
    required bool closedEnd,
  }) {
    final lineY = staffTopY - voltaLineSp * space;
    return VoltaGeometry(
      startX: startX,
      endX: endX,
      lineY: lineY,
      hookBottomY: lineY + voltaHookSp * space,
      closedEnd: closedEnd,
      labelOrigin: Offset(
        startX + voltaLabelInsetSp * space,
        lineY - voltaLabelRaiseSp * space,
      ),
    );
  }

  /// Whether [beat] lies under one of [voltas] (start inclusive, end
  /// exclusive).
  static bool withinVolta(double beat, Iterable<StaffVolta> voltas) {
    for (final v in voltas) {
      if (beat >= v.startBeat - 1e-6 && beat < v.endBeat - 1e-6) return true;
    }
    return false;
  }

  /// Baseline y of a navigation mark above a staff whose top line is
  /// [staffTopY]. A mark under a volta sits higher, above the volta label.
  static double navigationBaselineY({
    required double staffTopY,
    required double space,
    required bool overVolta,
  }) =>
      staffTopY -
      (overVolta ? navigationOverVoltaSp : navigationBaselineSp) * space;

  /// Label text of a jump mark (null for the glyph marks).
  static String? navigationLabel(NavigationKind kind) => switch (kind) {
    NavigationKind.dcAlFine => dcAlFineLabel,
    NavigationKind.dsAlCoda => dsAlCodaLabel,
    NavigationKind.segno || NavigationKind.coda => null,
  };

  /// Glyph of a sign mark (null for the text jump marks).
  static String? navigationGlyph(NavigationKind kind) => switch (kind) {
    NavigationKind.segno => segnoGlyph,
    NavigationKind.coda => codaGlyph,
    NavigationKind.dcAlFine || NavigationKind.dsAlCoda => null,
  };
}
