import 'dart:ui';

/// Shared key layout so keyboard and note lanes always align.
class KeyGeometry {
  KeyGeometry({
    required this.lowPitch,
    required this.highPitch,
    required this.size,
  }) : _whiteCount = _countWhite(lowPitch, highPitch);

  final int lowPitch;
  final int highPitch;
  final Size size;
  final int _whiteCount;

  static const _blackInOctave = {1, 3, 6, 8, 10};

  static bool isBlack(int pitch) => _blackInOctave.contains(pitch % 12);

  static int _countWhite(int lo, int hi) {
    var n = 0;
    for (var p = lo; p <= hi; p++) {
      if (!isBlack(p)) n++;
    }
    return n;
  }

  double get whiteWidth => size.width / _whiteCount;

  int _whiteIndex(int pitch) {
    var n = 0;
    for (var p = lowPitch; p < pitch; p++) {
      if (!isBlack(p)) n++;
    }
    return n;
  }

  Rect keyRect(int pitch) {
    final w = whiteWidth;
    if (!isBlack(pitch)) {
      return Rect.fromLTWH(_whiteIndex(pitch) * w, 0, w, size.height);
    }
    final left = _whiteIndex(pitch) * w - w * 0.3;
    return Rect.fromLTWH(left, 0, w * 0.6, size.height * 0.62);
  }

  /// Pitch under a point, black keys first; null when outside.
  int? pitchAt(Offset p) {
    for (var k = lowPitch; k <= highPitch; k++) {
      if (isBlack(k) && keyRect(k).contains(p)) return k;
    }
    for (var k = lowPitch; k <= highPitch; k++) {
      if (!isBlack(k) && keyRect(k).contains(p)) return k;
    }
    return null;
  }
}
