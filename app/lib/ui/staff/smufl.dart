/// SMuFL standard code points (Leland / Bravura standard).
abstract final class Smufl {
  static const gClef = '';
  static const fClef = '';
  static const noteheadWhole = '';
  static const noteheadHalf = '';
  static const noteheadBlack = '';
  static const accidentalSharp = '';
  static const accidentalFlat = '';
  static const accidentalNatural = '';
  static const restWhole = '';
  static const restHalf = '';
  static const restQuarter = '';
  static const rest8th = '';
  static const rest16th = '';

  // Flags for 8th and 16th notes
  static const flag8thUp = '\uE240';
  static const flag8thDown = '\uE241';
  static const flag16thUp = '\uE242';
  static const flag16thDown = '\uE243';

  // Time signatures
  static const timeSig0 = '';
  static const timeSig1 = '';
  static const timeSig2 = '';
  static const timeSig3 = '';
  static const timeSig4 = '';
  static const timeSig5 = '';
  static const timeSig6 = '';
  static const timeSig7 = '';
  static const timeSig8 = '';
  static const timeSig9 = '';

  static String? digitGlyph(int digit) => switch (digit) {
    0 => timeSig0,
    1 => timeSig1,
    2 => timeSig2,
    3 => timeSig3,
    4 => timeSig4,
    5 => timeSig5,
    6 => timeSig6,
    7 => timeSig7,
    8 => timeSig8,
    9 => timeSig9,
    _ => null,
  };
}
