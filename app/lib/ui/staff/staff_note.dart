/// One note on the grand staff, positioned in beats.
class StaffNote {
  const StaffNote(
    this.pitch,
    this.beat,
    this.beats, {
    this.leftHand = false,
    this.finger,
  });

  /// MIDI pitch (60 = middle C).
  final int pitch;

  /// Onset, in beats from the start of the piece.
  final double beat;

  /// Duration in beats (1 = quarter in 4/4).
  final double beats;
  final bool leftHand;

  /// Finger number 1-5 to print above the note, if any.
  final int? finger;
}

/// Ode to Joy (Beethoven, public domain), simplified, own arrangement.
/// Repeated [times] to stress the renderer with a long score.
List<StaffNote> odeToJoyDemo({int times = 24}) {
  // Right hand, one phrase pair (16 beats).
  const rh = <(int, double)>[
    (64, 1),
    (64, 1),
    (65, 1),
    (67, 1),
    (67, 1),
    (65, 1),
    (64, 1),
    (62, 1),
    (60, 1),
    (60, 1),
    (62, 1),
    (64, 1),
    (64, 1.5),
    (62, 0.5),
    (62, 2),
  ];
  // Left hand, one whole note per bar.
  const lh = <int>[48, 43, 48, 43];

  final notes = <StaffNote>[];
  var offset = 0.0;
  for (var t = 0; t < times; t++) {
    var b = offset;
    for (final (p, d) in rh) {
      notes.add(StaffNote(p, b, d));
      b += d;
    }
    for (var i = 0; i < lh.length; i++) {
      notes.add(StaffNote(lh[i], offset + i * 4, 4, leftHand: true));
    }
    offset += 16;
  }
  notes.sort((a, b) => a.beat.compareTo(b.beat));
  return notes;
}
