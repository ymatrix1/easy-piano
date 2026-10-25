import 'dart:math' as math;

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
  const ChordRun(this.text, {required this.scale, required this.riseEm});

  final String text;

  /// Font size relative to the root.
  final double scale;

  /// Baseline shift in root-font ems. Positive is up (superscript), negative
  /// is down (subscript).
  final double riseEm;

  @override
  String toString() => 'ChordRun($text, $scale, $riseEm)';
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
/// the same hand. The text `_` is an extension ([isExtension]): a line from
/// the previous lyric to the next one, or to the end of the note.
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
/// Follows MuseScore `rendering/score/harmonylayout.cpp` (chord symbol as
/// text above the staff, extension as a superscript and the bass as a
/// subscript after a slash) and `rendering/score/lyricslayout.cpp` (syllables
/// centred on the note, hyphens between syllables, melisma lines).
///
/// Text is drawn with the default sans font (not SMuFL), so the chord and
/// lyric sizes below are fractions of the staff space, not font metrics.
/// Melisma and hyphen values follow `data/styles/legacy-style-defaults-v450.mss`
/// (`lyricsMelismaPad` 0.2 sp, `lyricsDashMinLength` 0.4 sp,
/// `lyricsLineThickness` 0.1 sp, `lyricsMinDistance` 0.25 sp).
abstract final class HarmonyLayout {
  /// Root font size of a chord symbol, in staff spaces.
  static const chordSizeSp = 1.5;

  /// Scale of the extension run (superscript) and the bass run (subscript).
  static const suffixScale = 0.7;
  static const bassScale = 0.7;

  /// Extension raised so its top lines up with the root's cap height (about
  /// 0.22 root ems for a 0.7 scale run).
  static const suffixRiseEm = 0.22;

  /// Bass note dropped below the baseline (subscript).
  static const bassDropEm = 0.2;

  /// Gap between a chord symbol's baseline and the top staff line, or the top
  /// of the notes at its onset when those are higher.
  static const chordGapSp = 0.8;

  /// Lyric font size, in staff spaces.
  static const lyricSizeSp = 1.4;

  /// Top of the lyric row below its staff's bottom line, in staff spaces
  /// (MuseScore `lyricsMinTopDistance` 1 sp). Kept well above the default
  /// `lyricsPosBelow` (3 sp) so a treble row fits in a grand staff's gap.
  static const lyricTopSp = 1.0;

  /// Clearance between the lyric row and the lowest note ink above it
  /// (`lyricsMinDistance` 0.25 sp, plus a little margin for stems).
  static const lyricMinDistSp = 0.25;

  /// Hyphen and melisma line height above the lyric baseline.
  static const dashHeightSp = 0.35;

  /// Hyphen length limits and clearance from each syllable.
  static const hyphenMinSp = 0.2;
  static const hyphenMaxSp = 0.5;
  static const hyphenPadSp = 0.1;

  /// Melisma line clearance from each end, and its shortest length
  /// (`lyricsMelismaPad` 0.2 sp, `lyricsDashMinLength` 0.4 sp).
  static const dashPadSp = 0.2;
  static const dashMinSp = 0.4;

  /// Thickness of hyphens and melisma lines (`lyricsLineThickness` 0.1 sp).
  static const lineThicknessSp = 0.1;

  /// Text runs of [c], left to right: root at full size, extension raised,
  /// slash on the baseline, bass lowered and smaller.
  static List<ChordRun> chordRuns(ChordSymbol c) => [
    ChordRun(c.root, scale: 1, riseEm: 0),
    if (c.suffix.isNotEmpty)
      ChordRun(c.suffix, scale: suffixScale, riseEm: suffixRiseEm),
    if (c.bass != null) ...[
      const ChordRun('/', scale: 1, riseEm: 0),
      ChordRun(c.bass!, scale: bassScale, riseEm: -bassDropEm),
    ],
  ];

  /// Baseline of a chord symbol. It sits above the top staff line, and above
  /// the notes at its onset when those reach higher ([noteTopY] is their top
  /// ink, or null when there are none).
  static double chordBaselineY({
    required double staffTopY,
    double? noteTopY,
    required double space,
  }) {
    final top = noteTopY == null ? staffTopY : math.min(staffTopY, noteTopY);
    return top - chordGapSp * space;
  }

  /// Left edge of a lyric of [width] centred on the notehead centre [centreX].
  static double lyricLeft({required double centreX, required double width}) =>
      centreX - width / 2;

  /// Top of a lyric row below a staff. It sits [lyricTopSp] below the staff's
  /// bottom line, or lower when the lowest note ink of the row ([lowestInkY],
  /// null when none) would otherwise touch it.
  static double lyricTop({
    required double staffBottomY,
    double? lowestInkY,
    required double space,
  }) {
    final nominal = staffBottomY + lyricTopSp * space;
    if (lowestInkY == null) return nominal;
    return math.max(nominal, lowestInkY + lyricMinDistSp * space);
  }

  /// Baseline-relative height of hyphens and melisma lines.
  static double dashY({required double baselineY, required double space}) =>
      baselineY - dashHeightSp * space;

  /// Hyphen between a syllable ending at [prevRight] and the next one starting
  /// at [nextLeft]. Centred in the gap; null when the gap is too small.
  static ({double x0, double x1})? hyphenSegment({
    required double prevRight,
    required double nextLeft,
    required double space,
  }) {
    final avail = nextLeft - prevRight - 2 * hyphenPadSp * space;
    if (avail < hyphenMinSp * space) return null;
    final len = math.min(hyphenMaxSp * space, avail);
    final mid = (prevRight + nextLeft) / 2;
    return (x0: mid - len / 2, x1: mid + len / 2);
  }

  /// Melisma line from [fromX] to [toX] (the anchors of the lyrics before and
  /// after the extension), padded at both ends. Null when too short to draw.
  static ({double x0, double x1})? dashSegment({
    required double fromX,
    required double toX,
    required double space,
  }) {
    final x0 = fromX + dashPadSp * space;
    final x1 = toX - dashPadSp * space;
    if (x1 - x0 < dashMinSp * space) return null;
    return (x0: x0, x1: x1);
  }
}
