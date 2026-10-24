import 'dart:convert';
import 'dart:math' as math;

/// Represents a musical rest parsed from song notation (`r:<dur>`).
class SongRest {
  const SongRest({
    required this.beat,
    required this.beats,
    required this.leftHand,
    required this.voice,
  });

  final double beat;
  final double beats;
  final bool leftHand;
  final int voice;
}

abstract final class SongRestParser {
  /// Parses all rests (`r:...`) from a song JSON string.
  static List<SongRest> parseRests(
    String songJson, {
    int startBar = 0,
    int? endBar,
  }) {
    final rests = <SongRest>[];
    if (songJson.isEmpty) return rests;
    try {
      final decoded = jsonDecode(songJson);
      if (decoded is! Map<String, dynamic>) return rests;
      final rawBars = decoded['bars'];
      if (rawBars is! List) return rests;

      final timeSig = decoded['time'] as String? ?? '4/4';
      final parts = timeSig.split('/');
      final num = double.tryParse(parts[0]) ?? 4.0;
      final den = parts.length > 1 ? (double.tryParse(parts[1]) ?? 4.0) : 4.0;

      final lastBar = endBar != null
          ? math.min(endBar, rawBars.length)
          : rawBars.length;
      for (var b = startBar; b < lastBar; b++) {
        final barMap = rawBars[b];
        if (barMap is! Map) continue;
        final barStart = b * num;

        for (final entry in barMap.entries) {
          final handKey = entry.key.toString();
          if (handKey != 'RH' &&
              handKey != 'LH' &&
              handKey != 'RH2' &&
              handKey != 'LH2') {
            continue;
          }
          final text = entry.value.toString();
          final isLh = handKey.startsWith('LH');
          final voice = handKey.endsWith('2') ? 2 : 1;

          var t = 0.0;
          for (final rawTok in tokenize(text)) {
            final tok = rawTok.trim();
            if (tok.isEmpty || tok.startsWith('{')) continue;

            final colonIdx = tok.indexOf(':');
            if (colonIdx == -1) continue;

            final head = tok.substring(0, colonIdx);
            var tail = tok.substring(colonIdx + 1);

            // Strip (annotation)
            final parenIdx = tail.indexOf('(');
            if (parenIdx != -1) tail = tail.substring(0, parenIdx);

            // Strip @fingers
            final atIdx = tail.indexOf('@');
            if (atIdx != -1) tail = tail.substring(0, atIdx);

            final tokenBeats = parseDurBeats(tail, den);
            if (head == 'r') {
              rests.add(
                SongRest(
                  beat: barStart + t,
                  beats: tokenBeats,
                  leftHand: isLh,
                  voice: voice,
                ),
              );
            }
            t += tokenBeats;
          }
        }
      }
    } catch (_) {
      // Graceful fallback for non-json or malformed strings
    }
    return rests;
  }

  /// Splits one hand's bar string into tokens; `{...}` directives keep spaces.
  static List<String> tokenize(String bar) {
    final out = <String>[];
    int? start;
    var depth = 0;
    for (var i = 0; i < bar.length; i++) {
      final c = bar[i];
      if (c == '{') {
        depth++;
        start ??= i;
      } else if (c == '}') {
        depth = math.max(0, depth - 1);
      } else if (depth == 0 &&
          (c == ' ' || c == '\t' || c == '\n' || c == '\r')) {
        if (start != null) {
          out.add(bar.substring(start, i));
          start = null;
        }
      } else {
        start ??= i;
      }
    }
    if (start != null) {
      out.add(bar.substring(start));
    }
    return out;
  }

  /// Length of a duration token (`4`, `2.`, `3/8`) in beats of a `den` unit.
  static double parseDurBeats(String s, double den) {
    if (s.contains('/')) {
      final parts = s.split('/');
      final n = double.tryParse(parts[0]) ?? 1.0;
      final d = double.tryParse(parts[1]) ?? 4.0;
      if (d == 0) return 0.0;
      return (n / d) * den;
    }
    var dots = 0;
    while (dots < s.length && s[s.length - 1 - dots] == '.') {
      dots++;
    }
    final denStr = s.substring(0, s.length - dots);
    final denom = double.tryParse(denStr) ?? 4.0;
    if (denom == 0) return 0.0;
    var mult = 1.0;
    var add = 0.5;
    for (var d = 0; d < dots; d++) {
      mult += add;
      add /= 2;
    }
    return (den / denom) * mult;
  }
}
