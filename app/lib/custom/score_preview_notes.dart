import '../src/rust/api/practice.dart';
import '../ui/staff/song_rest_parser.dart';
import '../ui/staff/staff_note.dart';

/// Staff notes for the first [maxBeats] beats of a song, from the practice
/// session's targets (the same notes the practice stage draws).
List<StaffNote> staffNotesFromTargets(
  List<TargetView> targets, {
  required double maxBeats,
}) {
  final notes = <StaffNote>[];
  for (final t in targets) {
    if (t.beat >= maxBeats) continue;
    for (var k = 0; k < t.pitches.length; k++) {
      final p = t.pitches[k];
      notes.add(
        StaffNote(
          p,
          t.beat,
          k < t.noteBeats.length ? t.noteBeats[k] : t.beats,
          leftHand: k < t.leftHands.length ? t.leftHands[k] : p < 60,
          stemDown: k < t.stemDowns.length && t.stemDowns[k] ? true : null,
          twoStems: k < t.twoStems.length && t.twoStems[k],
          tie: k < t.ties.length && t.ties[k],
        ),
      );
    }
  }
  return notes;
}

/// Rests of the first [maxBeats] beats, as staff notes.
List<StaffNote> staffRestsFrom(
  List<SongRest> rests, {
  required double maxBeats,
}) {
  return [
    for (final r in rests)
      if (r.beat < maxBeats)
        StaffNote(
          r.leftHand ? 48 : 72,
          r.beat,
          r.beats,
          leftHand: r.leftHand,
          voice: r.voice,
          isRest: true,
        ),
  ];
}

/// The preview notes of [songJson]: calls the Rust core (`PracticeSession`), so it
/// needs the bridge initialised.
List<StaffNote> previewNotesOf(
  String songJson, {
  required double maxBeats,
  required int bars,
}) {
  final session = PracticeSession.create(
    songJson: songJson,
    mode: 'wait',
    input: 'touch',
    hand: 'both',
    tempo: 1.0,
    passRatio: 0.8,
    failedAttempts: 0,
    training: false,
  );
  final notes = [
    ...staffNotesFromTargets(session.targets(), maxBeats: maxBeats),
    ...staffRestsFrom(
      SongRestParser.parseRests(songJson, endBar: bars),
      maxBeats: maxBeats,
    ),
  ]..sort((a, b) => a.beat.compareTo(b.beat));
  return notes;
}
