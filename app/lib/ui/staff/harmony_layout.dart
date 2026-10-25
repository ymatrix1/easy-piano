import 'dart:math' as math;

import 'dynamics_layout.dart';

/// A parsed chord symbol: `root` (letter plus optional `#` or `b`), `suffix`
/// (quality and extensions, possibly empty) and `bass` (the note after a
/// slash, or null). Examples: `C`, `Am7`, `G7/B`, `F#m7b5`, `Bb`.
class ChordSymbol {
  const ChordSymbol({required this.root, this.suffix = '', this.bass});

  final String root;
  final String suffix;
  final String? bass;

  /// Letter, optional accidental, then a suffix of letters, digits and
  /// `+ - ( ) # ° ø`, then an optional `/` and a bass note.
  static final _pattern = RegExp(
    r'^([A-G][#b]?)([0-9A-Za-z+\-()#°ø]*)(?:/([A-G][#b]?))?$',
  );

  static const _maxLength = 16;

  /// Parses chord text. Returns null for anything that is not a chord symbol
  /// (lower-case root, empty bass after the slash, spaces, a second slash).
  static ChordSymbol? parse(String text) {
    if (text.isEmpty || text.length > _maxLength) return null;
    final m = _pattern.firstMatch(text);
    if (m == null) return null;
    return ChordSymbol(
      root: m.group(1)!,
      suffix: m.group(2) ?? '',
      bass: m.group(3),
    );
  }
}

/// One text run of a chord symbol, drawn left to right.
class ChordRun {
  const ChordRun(
    this.text, {
    required this.scale,
    this.riseSp = 0,
    this.dxSp = 0,
  });

  final String text;

  /// Font size relative to the root.
  final double scale;

  /// Baseline shift in staff spaces. Positive is up, negative is down.
  final double riseSp;

  /// Horizontal shift of this run's ink in staff spaces. The pen does not
  /// move, so the next run starts where it would have without the shift.
  final double dxSp;

  @override
  String toString() => 'ChordRun($text, $scale, $riseSp, $dxSp)';
}

/// A chord symbol at [beat] (`{chord:"Am7"}`), attached to the note that
/// starts at that beat in the hand the directive sits in.
class StaffChord {
  const StaffChord(this.beat, this.symbol, {this.leftHand = false});

  final double beat;
  final ChordSymbol symbol;

  /// True when the directive sits in a left-hand (`LH`) bar.
  final bool leftHand;
}

/// One lyric item of a hand (`{lyric:"..."}`).
///
/// A syllable is drawn centred under the notehead at [beat]. A trailing `-`
/// in the directive sets [hyphen]: a hyphen joins it to the next syllable of
/// the same hand. The text `_` is an extension ([isExtension]): a melisma
/// line from the syllable before it to the notehead of the last extension.
class StaffLyric {
  const StaffLyric(
    this.beat,
    this.text, {
    this.hyphen = false,
    this.leftHand = false,
  });

  const StaffLyric.extension(this.beat, {this.leftHand = false})
    : text = '',
      hyphen = false;

  final double beat;

  /// Syllable text without the hyphen; empty for an extension.
  final String text;

  /// The syllable ends a word and a hyphen follows it.
  final bool hyphen;

  /// True when the directive sits in a left-hand (`LH`) bar.
  final bool leftHand;

  bool get isExtension => text.isEmpty;

  /// A syllable: no spaces, no `_`, `{`, `}`, `"` or inner `-`.
  static final _syllable = RegExp(r'^[^\s_{}"\-]+$');

  static const _maxLength = 24;

  /// Parses the text of a `{lyric:"..."}` directive. Returns null when the
  /// text is neither `_` nor a syllable (optionally ending in `-`).
  static StaffLyric? fromDirective(
    double beat,
    String raw, {
    bool leftHand = false,
  }) {
    if (raw == '_') return StaffLyric.extension(beat, leftHand: leftHand);
    if (raw.isEmpty || raw.length > _maxLength) return null;
    final hyphen = raw.endsWith('-');
    final body = hyphen ? raw.substring(0, raw.length - 1) : raw;
    if (!_syllable.hasMatch(body)) return null;
    return StaffLyric(beat, body, hyphen: hyphen, leftHand: leftHand);
  }
}

/// Chord symbol and lyric geometry. Pure functions, no painting state.
///
/// Follows MuseScore `rendering/score/harmonylayout.cpp` and
/// `rendering/score/lyricslayout.cpp`. Every constant below cites the style
/// value (`style/styledef.cpp`, or `data/styles/legacy-style-defaults-v450.mss`
/// where the two differ, noted) or the chord token file
/// (`data/chords/chords_legacy.xml`). Constants marked "local choice" are not
/// from MuseScore.
///
/// Text uses the app's default sans font, not Edwin (MuseScore's default
/// chord and lyric font). Sizes are set so the em matches MuseScore's 10 pt.
/// Glyph shapes and widths therefore differ.
abstract final class HarmonyLayout {
  // ---- Chord symbols ----

  /// Root font size, in staff spaces. 10 pt Edwin, spatium dependent
  /// (`chordSymbolAFontSize` 10, styledef.cpp:433; v450 mss:291). 1 pt is
  /// 1/72 inch and the default spatium is 1.75 mm (styledef.cpp:804), so
  /// 10 pt = 10 * 25.4 / 72 / 1.75 = 2.016 sp.
  static const chordSizeSp = 10 * 25.4 / 72 / 1.75;

  /// Extension run: same size as the root (`chordExtensionMag` 1.0,
  /// styledef.cpp:551; chordlist.cpp:2058-2059 multiplies it into the font).
  /// The chord style JAZZ alone raises modifiers as superscripts
  /// (chordlist.cpp:1625, 1707-1713). That is not implemented.
  static const suffixScale = 1.0;

  /// Extension baseline offset: none (`chordExtensionAdjust` 0.0,
  /// styledef.cpp:552; chordlist.cpp:1580-1581 returns it as the y offset).
  static const suffixRiseSp = 0.0;

  /// The slash is lowered 1/5 sp and moved 1/5 sp left of the pen before it
  /// is drawn (`m:-0.2:1 / m:0.2:1` in renderBase, chords_legacy.xml:411).
  /// Legacy units of 1/5 sp are converted by compatutils.cpp:594-606 (file
  /// version 1.24, chordlist.cpp:2105, 357-362).
  static const slashDropSp = 0.2;
  static const slashShiftSp = 0.04;

  /// The bass note is at root size (`chordBassNoteScale` 1.0, styledef.cpp:558;
  /// chordlist.cpp:1620-1621 and harmonylayout.cpp:572-584 use it as the
  /// scale).
  static const bassScale = 1.0;

  /// The bass note is lowered 2/5 sp: the slash's 1/5 sp plus another 1/5 sp
  /// (renderBase: `m:0.2:1 :n` after the slash, chords_legacy.xml:411).
  static const bassDropSp = 0.4;

  /// Baseline above the top staff line (`chordSymbolAPosAbove` y -2.5,
  /// styledef.cpp:420; v450 mss:282). The harmony sits on the ON_STAFF
  /// position and defaultPos adds this offset (harmonylayout.cpp:202-206).
  static const chordAboveStaffSp = 2.5;

  /// Clearance from the notes at the onset. The autoplace pass lifts the
  /// symbol so that its shape clears the skyline by `minHarmonyDistance`
  /// (styledef.cpp:407; v450 mss:272; systemlayout.cpp:1101-1108;
  /// autoplace.cpp:109-116). Only noteheads are used here; stems and other
  /// elements are not (local simplification).
  static const chordNoteClearanceSp = 0.5;

  // ---- Lyrics ----

  /// Lyric font size, in staff spaces. 10 pt Edwin, spatium dependent
  /// (`lyricsOddFontSize` 10, styledef.cpp:141; v450 mss:57-60). Same
  /// conversion as [chordSizeSp]: 2.016 sp.
  static const lyricSizeSp = 10 * 25.4 / 72 / 1.75;

  /// Top of the lyric row below its staff's bottom line, in staff spaces.
  /// LOCAL CHOICE. MuseScore's default baseline is `lyricsPosBelow` 3 sp below
  /// the staff (styledef.cpp:109; v450 mss:35; lyricslayout.cpp:612-614). This
  /// app uses 1 sp (the minimum below) so a treble row fits in a grand staff's
  /// gap. Deliberate deviation, see sheet-engraving.md.
  static const lyricTopSp = 1.0;

  /// Clearance between the lyric row and the lowest note ink of the row above
  /// it. MuseScore keeps `lyricsMinTopDistance` 1 sp between the lyric and the
  /// staff skyline (styledef.cpp:110; v450 mss:36; lyricslayout.cpp:630-660),
  /// and the skyline includes stems and noteheads below the staff.
  static const lyricClearanceSp = 1.0;

  /// Hyphen and melisma clearance from a syllable: `lyricsDashPad` 0.05 sp
  /// (styledef.cpp:124; v450 mss:49). Used at both ends of a hyphen
  /// (lyricslayout.cpp:831, 811).
  static const dashPadSp = 0.05;

  /// Shortest hyphen. A shorter gap is widened to this, symmetrically
  /// (`lyricsDashMinLength` 0.4 sp, styledef.cpp:114; v450 mss:40;
  /// lyricslayout.cpp:329-340).
  static const dashMinSp = 0.4;

  /// Longest hyphen (`lyricsDashMaxLength` 0.6 sp, styledef.cpp:115; v450
  /// mss:41; lyricslayout.cpp:342).
  static const dashMaxSp = 0.6;

  /// One extra hyphen per 16 sp of gap (`lyricsDashMaxDistance` 16 sp,
  /// styledef.cpp:116; v450 mss:42; lyricslayout.cpp:317-323). Not used for
  /// gaps under 16 sp, where a hyphen is always drawn (`lyricsDashForce`
  /// true, styledef.cpp:117; v450 mss:43).
  static const dashMaxDistanceSp = 16.0;

  /// Height of hyphen and melisma lines above the lyric baseline:
  /// `lyricsDashYposRatio` 0.5 of the lyric x-height (styledef.cpp:126; v450
  /// mss:51). LOCAL CHOICE for x-height: 0.5 em (Edwin metrics are not in this
  /// repo; a typical sans x-height is about 0.5 em).
  static const dashYposRatio = 0.5;
  static const xHeightEm = 0.5;
  static const dashHeightSp = dashYposRatio * xHeightEm * lyricSizeSp;

  /// Melisma line: padding after the syllable before it (`lyricsMelismaPad`
  /// 0.2 sp, styledef.cpp:123; v450 mss:48; lyricslayout.cpp:777).
  static const melismaPadSp = 0.2;

  /// Shortest melisma line. A shorter one is not drawn, since
  /// `lyricsMelismaForce` is false (`lyricsMelismaMinLength` 1 sp,
  /// styledef.cpp:130 and 129; v450 mss:54 and 53; lyricslayout.cpp:247-254).
  static const melismaMinSp = 1.0;

  /// Tolerance on [melismaMinSp] (lyricslayout.cpp:246).
  static const melismaToleranceSp = 0.05;

  /// Thickness of hyphens and melisma lines: `lyricsDashLineThickness` 0.1 sp
  /// (styledef.cpp:125) and `lyricsLineThickness` 0.1 sp (styledef.cpp:120).
  static const lineThicknessSp = 0.1;

  /// Width of a notehead, in staff spaces, used as the melisma end anchor
  /// (`noteheadBlack` 1.18, `noteheadWhole` 1.688; see [DynamicsLayout]).
  static double headWidthSp({required bool whole}) => whole
      ? DynamicsLayout.noteheadWholeWidthSp
      : DynamicsLayout.noteheadWidthSp;

  /// Text runs of [c], left to right: root at full size, extension at the
  /// same size and baseline, slash lowered 1/5 sp and shifted left 1/25 sp,
  /// bass at full size and lowered 2/5 sp.
  static List<ChordRun> chordRuns(ChordSymbol c) => [
    ChordRun(c.root, scale: 1, riseSp: 0),
    if (c.suffix.isNotEmpty)
      ChordRun(c.suffix, scale: suffixScale, riseSp: suffixRiseSp),
    if (c.bass != null) ...[
      const ChordRun('/', scale: 1, riseSp: -slashDropSp, dxSp: -slashShiftSp),
      ChordRun(c.bass!, scale: bassScale, riseSp: -bassDropSp),
    ],
  ];

  /// Baseline of a chord symbol. The default is [chordAboveStaffSp] above the
  /// top staff line. It is lifted, if needed, so the notes at its onset keep
  /// [chordNoteClearanceSp] clear ([noteTopY] is their highest notehead top,
  /// or null when there are none).
  static double chordBaselineY({
    required double staffTopY,
    double? noteTopY,
    required double space,
  }) {
    final nominal = staffTopY - chordAboveStaffSp * space;
    if (noteTopY == null) return nominal;
    return math.min(nominal, noteTopY - chordNoteClearanceSp * space);
  }

  /// Left edge of a lyric of [width] centred on the notehead centre [centreX].
  static double lyricLeft({required double centreX, required double width}) =>
      centreX - width / 2;

  /// Top of a lyric row below a staff. It sits [lyricTopSp] below the staff's
  /// bottom line. It is lowered when the lowest note ink of the row
  /// ([lowestInkY], null when none) comes within [lyricClearanceSp].
  static double lyricTop({
    required double staffBottomY,
    double? lowestInkY,
    required double space,
  }) {
    final nominal = staffBottomY + lyricTopSp * space;
    if (lowestInkY == null) return nominal;
    return math.max(nominal, lowestInkY + lyricClearanceSp * space);
  }

  /// Height of hyphens and melisma lines above the lyric baseline.
  static double dashY({required double baselineY, required double space}) =>
      baselineY - dashHeightSp * space;

  /// Hyphen segments between a syllable ending at [prevRight] and the next
  /// one starting at [nextLeft]. This follows MuseScore's dash layout. The
  /// line is padded by [dashPadSp] at each end. A gap under [dashMinSp] is
  /// widened symmetrically. One hyphen per [dashMaxDistanceSp] of length,
  /// each centred on its part, at most [dashMaxSp] long. A hyphen is always
  /// drawn, since `lyricsDashForce` is on.
  static List<({double x0, double x1})> hyphenSegments({
    required double prevRight,
    required double nextLeft,
    required double space,
  }) {
    final from = prevRight + dashPadSp * space;
    final to = nextLeft - dashPadSp * space;
    final gap = to - from;
    final minLen = dashMinSp * space;
    final len = math.max(gap, minLen);
    final start = gap < minLen ? from - (minLen - gap) / 2 : from;
    final maxDist = dashMaxDistanceSp * space;
    final count = len > maxDist ? (len / maxDist).ceil() : 1;
    final step = len / count;
    final width = math.min(len, dashMaxSp * space);
    return [
      for (var i = 0; i < count; i++)
        (
          x0: start + (i + 0.5) * step - width / 2,
          x1: start + (i + 0.5) * step + width / 2,
        ),
    ];
  }

  /// Melisma line from [textRight], the right edge of the syllable before it,
  /// to [headRight], the right edge of the notehead of the last extension.
  /// It starts [melismaPadSp] after the syllable. Null when shorter than
  /// [melismaMinSp] (not forced).
  static ({double x0, double x1})? melismaSegment({
    required double textRight,
    required double headRight,
    required double space,
  }) {
    final x0 = textRight + melismaPadSp * space;
    final x1 = headRight;
    if (x1 - x0 < (melismaMinSp - melismaToleranceSp) * space) return null;
    return (x0: x0, x1: x1);
  }
}
