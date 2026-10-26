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
enum NavigationKind {
  segno,
  coda,
  dcAlFine,
  dsAlFine,
  dcAlCoda,
  dsAlCoda,
  fine,
  toCoda,
}

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
    required this.leftDots,
  });

  /// Centre x of each thin line.
  final List<double> thinX;

  /// Centre x of each thick line.
  final List<double> thickX;

  /// Left edge of each dot pair (origin of the `repeatDot` glyph).
  final List<double> dotsX;

  final double thinWidth;
  final double thickWidth;

  /// Outermost ink on the left (thick line or dots) and on the right.
  final double left;
  final double right;

  /// The group starts with the dots (`:|`, `:|:`), not with the thick line
  /// (`|:`).
  final bool leftDots;
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
/// Every number is either a MuseScore value, with its source in the comment
/// (file:line under `references/MuseScore/src/engraving`, or "v450:line" for
/// `data/styles/legacy-style-defaults-v450.mss`), a glyph metric measured on
/// `app/assets/fonts/Leland.otf` (1000 units per em, 1 em = 4 staff spaces,
/// SMuFL), or a local choice, marked "local" in the comment. Local choices are
/// listed in docs/specs/sheet-engraving.md (section 5).
///
/// Glyph codepoints are SMuFL names from `fonts/smufl/glyphnames.json`.
/// Leland has no `repeatLeft` (U+E040), `repeatRight` (U+E041), `dalSegno`
/// (U+E045) or `daCapo` (U+E046): the bar lines are drawn as lines (MuseScore
/// draws them as lines too, `tdraw.cpp`) and the D.C./D.S. marks as text.
abstract final class RepeatLayout {
  /// `repeatDot` (U+E044): one dot. Leland bbox 0..104 x -53..53 units, so
  /// 0.416 sp wide and centred on the baseline. Source: `tdraw.cpp:692-693`
  /// (`drawDots` draws each dot at its baseline).
  static const repeatDotGlyph = '\uE044';

  /// `repeatDots` (U+E043): both dots in one glyph (not used, listed for
  /// reference; MuseScore's `drawDots` draws two `repeatDot` symbols).
  static const repeatDotsGlyph = '\uE043';

  /// `segno` (U+E047) and `coda` (U+E048): present in Leland. Leland bboxes
  /// start at x 0: segno 0..654 units, coda 0..745 units.
  static const segnoGlyph = '\uE047';
  static const codaGlyph = '\uE048';

  /// Text labels for the jump marks (no Leland glyph for them). Source:
  /// `dom/jump.cpp:51` (`DC_AL_FINE` "D.C. al Fine") and `dom/jump.cpp:53`
  /// (`DS_AL_CODA` "D.S. al Coda").
  static const dcAlFineLabel = 'D.C. al Fine';
  static const dsAlCodaLabel = 'D.S. al Coda';
  static const dcAlCodaLabel = 'D.C. al Coda';
  static const dsAlFineLabel = 'D.S. al Fine';
  static const fineLabel = 'Fine';
  static const toCodaLabel = 'To Coda';

  /// Default spatium in mm (`spatium` 1.74978, v450:1606). Used to turn MuseScore
  /// point sizes into staff spaces: 1 in = 72 pt = 25.4 mm (standard
  /// conversion, local choice of unit handling).
  static const defaultSpatiumMm = 1.74978;
  static const ptPerSpatium = defaultSpatiumMm * 72 / 25.4;

  /// Thin barline width, `barWidth` 0.18 (v450:91). Drawn at `tdraw.cpp:733-735`
  /// and `:816`.
  static const thinWidthSp = 0.18;

  /// Thick barline width, `endBarWidth` 0.55 (v450:93). `tdraw.cpp:811`.
  static const thickWidthSp = 0.55;

  /// Gap between the thin and the thick line, `endBarDistance` 0.37 (v450:95).
  /// `tdraw.cpp:818` (START_REPEAT) and `:842` (END_REPEAT).
  static const thickGapSp = 0.37;

  /// Gap between a line and the dots, `repeatBarlineDotSeparation` 0.37
  /// (v450:96). `tdraw.cpp:821` and `:838`.
  static const dotSeparationSp = 0.37;

  /// Advance width of one `repeatDot` glyph: its Leland bbox (0.416 sp).
  /// MuseScore reads the same value with `symBbox(repeatDot).width()`
  /// (`tdraw.cpp:837`).
  static const dotsWidthSp = 0.416;

  /// Dot centres above the bottom staff line: 1.5 sp (lower dot, space 2) and
  /// 2.5 sp (upper dot, space 3). Source: `tdraw.cpp:683-684` gives, for 5
  /// lines measured from the top line, y1 = `(lines-1)/2 - 0.5` = 1.5 and
  /// y2 = `lines/2 + 0.5` = 2.5 line distances. The bottom line is 4 line
  /// distances below the top line, so y1 is 2.5 sp above it and y2 is 1.5 sp
  /// above it. `drawDots` draws the upper dot at y1 and the lower at y2.
  static const dotLowerSp = 1.5;
  static const dotUpperSp = 2.5;

  /// Volta line height above the top staff line, `voltaPosAbove` y=-3
  /// (v450:490). The default position of a volta comes from
  /// `dom/volta.cpp:417-419` (`defaultPosSid` returns `voltaPosAbove`).
  static const voltaLineSp = 3.0;

  /// Length of the volta's down hooks, `voltaHook` 2.2 (v450:491).
  /// `dom/volta.cpp:71-72` (`BEGIN_HOOK_HEIGHT`, `END_HOOK_HEIGHT`).
  static const voltaHookSp = 2.2;

  /// Volta line thickness, `voltaLineWidth` 0.11 (v450:492).
  /// `dom/volta.cpp:67` (`LINE_WIDTH`).
  static const voltaLineWidthSp = 0.11;

  /// Volta label offset from its start point, `voltaOffset` x=0.6 y=2.2
  /// (v450:503), applied as the begin text offset at
  /// `rendering/score/tlayout.cpp:5977`. The label is placed `BELOW` the line
  /// (`dom/volta.cpp:109`, `setBeginTextPlace(TextPlace::BELOW)`), left and
  /// baseline aligned (`voltaAlign` left,baseline, v450:502).
  static const voltaLabelOffsetXSp = 0.6;
  static const voltaLabelOffsetYSp = 2.2;

  /// Volta label font size, `voltaFontSize` 11 pt (v450:497), spatium
  /// dependent (v450:499), bold (`voltaFontStyle` 1 = `FontStyle::Bold`,
  /// v450:500, `types.h:1069`). The font face is Edwin in MuseScore
  /// (v450:496); not available here, the app's default font is used (local).
  static const voltaFontSizePt = 11.0;

  /// Jump label font size, `repeatRightFontSize` 11 pt (v450:1094), spatium
  /// dependent (v450:1096), normal style (`repeatRightFontStyle` 0, v450:1097).
  /// Edwin in MuseScore (v450:1093), default font here (local).
  static const jumpFontSizePt = 11.0;

  /// Segno and coda symbol size, `MUSIC_SYMBOL_SIZE` 18 pt (`dom/marker.cpp:182-183`).
  static const markerSymbolSizePt = 18.0;

  /// Leland advance widths of the marker glyphs, in em (1000 units per em).
  /// Used to centre the glyph on its x: `Marker` uses `MARKER_CENTER_ON_SYMBOL`
  /// true (`dom/marker.cpp:180-181`).
  static const segnoWidthEm = 0.654;
  static const codaWidthEm = 0.745;

  /// Navigation mark baseline above the top staff line, `markerPosAbove` y=-2
  /// (v450:644) for segno and coda, and `jumpPosAbove` y=-2 (v450:643) for
  /// the jump text. Both placements are `ABOVE` (`dom/marker.cpp:178-179`,
  /// `repeatRightPlacement` 0 for jumps, v450:1100 and `repeatLeftPlacement`
  /// 0, v450:1086).
  static const navigationBaselineSp = 2.0;

  /// Mark over a volta: the volta line is `voltaLineSp` above the staff, and
  /// MuseScore autoplace keeps the mark `repeatMinDistance` (0.5, v450:1549)
  /// above the volta (`markerStyle` maps it to `MIN_DISTANCE`,
  /// `dom/marker.cpp:44`). Approximation: autoplace itself is not replicated,
  /// and the volta line's half width is ignored.
  static const repeatMinDistanceSp = 0.5;
  static const navigationOverVoltaSp = voltaLineSp + repeatMinDistanceSp;

  /// Geometry of one repeat barline group whose origin is [x0], in screen x.
  ///
  /// Source: `rendering/score/tdraw.cpp:810-849` (`START_REPEAT`,
  /// `END_REPEAT`). Start (`|:`): thick, thin, dots. End (`:|`): dots, thin,
  /// thick. Both (`:|:`, `tdraw.cpp:851-882`): dots, thin, thick, thin, dots.
  /// The group width is `tlayout.cpp:1044-1050` (`barLineWidth`), the width
  /// the segment reserves for the barline (`measurelayout.cpp:947-956`).
  ///
  /// Local choice: the painter places the group centred on [x], the x of a
  /// plain bar line (`SegmentLayout.barLineX`). MuseScore instead starts the
  /// group at the segment origin and reserves its width in the spacing. This
  /// painter reserves no width, so the group can touch the notes beside it.
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
      // tdraw.cpp:813 thick centre lw2/2; :818 thin after endBarDistance;
      // :821 dots after dotSeparation.
      thickX.add(thick / 2);
      thinX.add(thickX.last + thick / 2 + gap + thin / 2);
      dotsX.add(thinX.last + thin / 2 + sep);
      left = 0;
      right = dotsX.last + dotW;
    } else if (end && !start) {
      // tdraw.cpp:834-835 dots at origin; :837-839 thin after dot width and sep;
      // :842-844 thick after endBarDistance.
      dotsX.add(0);
      thinX.add(dotW + sep + thin / 2);
      thickX.add(thinX.last + thin / 2 + gap + thick / 2);
      left = 0;
      right = thickX.last + thick / 2;
    } else if (start && end) {
      // tdraw.cpp:855-882: dots, thin, thick, thin, dots.
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
        leftDots: false,
      );
    }

    // Centre the group's ink on [x] (local choice, see above).
    final shift = x - right / 2;
    return RepeatBarlineGeometry(
      thinX: [for (final v in thinX) v + shift],
      thickX: [for (final v in thickX) v + shift],
      dotsX: [for (final v in dotsX) v + shift],
      thinWidth: thin,
      thickWidth: thick,
      left: left + shift,
      right: right + shift,
      leftDots: end,
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

  /// x of a volta's left end, from the MuseScore rule `Volta::linePos`
  /// (`dom/volta.cpp:356-376`): the line starts at the barline segment's x plus
  /// its width, minus half the line width (`x += -0.5 * lineWidth`, volta.cpp:376).
  ///
  /// With a repeat group, the segment width is the group width (`tlayout.cpp:1044-1050`),
  /// so the start is `group.right - voltaLineWidth / 2`. Without a repeat, the
  /// bar line is a plain line ([barX] is its centre, `tdraw.cpp:733-735`), so
  /// the segment starts at `barX - barWidth / 2` and its width is `barWidth`:
  /// the start is `barX + (barWidth - voltaLineWidth) / 2`.
  static double voltaStartX({
    required double barX,
    required RepeatBarlineGeometry? group,
    required double space,
  }) => group == null
      ? barX + (thinWidthSp - voltaLineWidthSp) / 2 * space
      : group.right - voltaLineWidthSp / 2 * space;

  /// x of a volta's right end, from `Volta::linePos` (`dom/volta.cpp:378-391`).
  /// The end is the barline's origin plus `voltaLineWidth / 2`. With an
  /// `:|` / `:|:` group the origin is past the dots (`volta.cpp:387-388`:
  /// dot width plus `repeatBarlineDotSeparation`). With a plain bar line or a
  /// `|:` group there is no dot offset (`volta.cpp:390`).
  static double voltaEndX({
    required double barX,
    required RepeatBarlineGeometry? group,
    required double space,
  }) {
    final half = voltaLineWidthSp / 2 * space;
    if (group == null) {
      // Origin = barX - barWidth / 2 (tdraw.cpp:735); end = origin + lw / 2.
      return barX - (thinWidthSp - voltaLineWidthSp) / 2 * space;
    }
    if (group.leftDots) {
      // The origin is the dots' left edge; end = origin + dotWidth +
      // repeatBarlineDotSeparation + lw / 2 (volta.cpp:387-390).
      return group.left + dotsWidthSp * space + dotSeparationSp * space + half;
    }
    return group.left + half;
  }

  /// Volta line, hooks and label for a volta from [startX] to [endX], above a
  /// staff whose top line is [staffTopY].
  ///
  /// The label is placed below the line at `voltaOffset` (x 0.6, y 2.2 sp,
  /// v450:503), see [voltaLabelOffsetXSp].
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
        startX + voltaLabelOffsetXSp * space,
        lineY + voltaLabelOffsetYSp * space,
      ),
    );
  }

  /// Font size in pixels of a volta label (`voltaFontSize` 11 pt, spatium
  /// dependent: pt / ptPerSpatium staff spaces).
  static double voltaFontSize(double space) =>
      voltaFontSizePt / ptPerSpatium * space;

  /// Font size in pixels of a jump label (`repeatRightFontSize` 11 pt).
  static double jumpFontSize(double space) =>
      jumpFontSizePt / ptPerSpatium * space;

  /// Em size in pixels of a segno or coda glyph (`MUSIC_SYMBOL_SIZE` 18 pt).
  static double navigationGlyphEm(double space) =>
      markerSymbolSizePt / ptPerSpatium * space;

  /// Glyph origin x of a segno or coda centred on [x] (`MARKER_CENTER_ON_SYMBOL`).
  static double navigationGlyphOriginX({
    required NavigationKind kind,
    required double x,
    required double space,
  }) {
    final widthEm = kind == NavigationKind.coda ? codaWidthEm : segnoWidthEm;
    return x - widthEm * navigationGlyphEm(space) / 2;
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
  /// [staffTopY]. A mark under a volta sits higher, above the volta line.
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
    NavigationKind.dcAlCoda => dcAlCodaLabel,
    NavigationKind.dsAlFine => dsAlFineLabel,
    NavigationKind.fine => fineLabel,
    NavigationKind.toCoda => toCodaLabel,
    NavigationKind.segno || NavigationKind.coda => null,
  };

  /// Glyph of a sign mark (null for the text jump marks).
  static String? navigationGlyph(NavigationKind kind) => switch (kind) {
    NavigationKind.segno => segnoGlyph,
    NavigationKind.coda => codaGlyph,
    NavigationKind.dcAlFine ||
    NavigationKind.dsAlFine ||
    NavigationKind.dcAlCoda ||
    NavigationKind.dsAlCoda ||
    NavigationKind.fine ||
    NavigationKind.toCoda => null,
  };
}
