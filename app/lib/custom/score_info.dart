import 'dart:convert';

/// How hard a score looks: a rough guess from its notes, shown as a hint.
enum ScoreLevel { beginner, intermediate, advanced }

/// What the preview shows about an imported score, read from its content song JSON
/// (docs/specs/content-format.md).
class ScoreInfo {
  const ScoreInfo({
    required this.key,
    required this.bpm,
    required this.timeSignature,
    required this.bars,
    required this.rightHand,
    required this.leftHand,
    required this.level,
  });

  factory ScoreInfo.fromSongJson(String songJson) {
    final song = jsonDecode(songJson) as Map<String, dynamic>;
    final bars = [
      for (final b in song['bars'] as List) (b as Map<String, dynamic>),
    ];
    var rh = false;
    var lh = false;
    var notes = 0;
    var accidentals = 0;
    final pitches = <int>[];
    for (final bar in bars) {
      for (final entry in bar.entries) {
        final hand = entry.key;
        for (final token in (entry.value as String).split(RegExp(r'\s+'))) {
          final p = _pitchOf(token);
          if (p == null) continue;
          // A hand counts once it plays a note: the importer writes `r:1` for a
          // hand with nothing to play.
          if (hand.startsWith('RH')) rh = true;
          if (hand.startsWith('LH')) lh = true;
          notes++;
          pitches.add(p);
          if (RegExp(r'^[A-G][#b]').hasMatch(token)) accidentals++;
        }
      }
    }
    final perBar = bars.isEmpty ? 0.0 : notes / bars.length;
    final span = pitches.isEmpty
        ? 0
        : pitches.reduce((a, b) => a > b ? a : b) -
              pitches.reduce((a, b) => a < b ? a : b);
    final bpm = (song['bpm'] as num).toDouble();
    final points =
        (perBar > 12 ? 2 : (perBar > 6 ? 1 : 0)) +
        (span > 24 ? 1 : 0) +
        (accidentals * 6 > notes && notes > 0 ? 1 : 0) +
        (rh && lh ? 1 : 0) +
        (bpm > 120 ? 1 : 0);
    return ScoreInfo(
      key: (song['key'] as String?) ?? 'C',
      bpm: bpm.round(),
      timeSignature: song['time'] as String,
      bars: bars.length,
      rightHand: rh,
      leftHand: lh,
      level: points >= 4
          ? ScoreLevel.advanced
          : (points >= 2 ? ScoreLevel.intermediate : ScoreLevel.beginner),
    );
  }

  final String key;
  final int bpm;
  final String timeSignature;
  final int bars;
  final bool rightHand;
  final bool leftHand;
  final ScoreLevel level;
}

/// MIDI pitch of a bar token such as `C#4:4@3`, or null for a rest or directive.
int? _pitchOf(String token) {
  final m = RegExp(r'^([A-G])([#b]?)(-?\d)').firstMatch(token);
  if (m == null) return null;
  const base = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
  final acc = m.group(2) == '#' ? 1 : (m.group(2) == 'b' ? -1 : 0);
  return (int.parse(m.group(3)!) + 1) * 12 + base[m.group(1)]! + acc;
}
