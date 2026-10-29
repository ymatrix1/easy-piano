import 'package:flutter/material.dart';

import '../practice/practice_stage.dart' show StagePalette, fitStaves;
import '../ui/staff/staff_note.dart';
import '../ui/staff/staff_painter.dart';

/// The first bars of a score on a white staff band, as the practice stage draws them.
class ScoreStaffStrip extends StatelessWidget {
  const ScoreStaffStrip({
    super.key,
    required this.notes,
    required this.beats,
    required this.beatsPerBar,
    required this.keyFifths,
    this.height = 150,
  });

  final List<StaffNote> notes;

  /// Beats shown, from the first beat.
  final double beats;
  final double beatsPerBar;
  final int keyFifths;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, c) {
            // Leave room for the clef and key signature on the left.
            final usable = (c.maxWidth - 96).clamp(40.0, double.infinity);
            return CustomPaint(
              painter: StaffPainter(
                notes: notes,
                playheadBeat: ValueNotifier(0),
                inkColor: StagePalette.ink,
                staffColor: StagePalette.ink,
                playheadColor: StagePalette.playBar,
                bandColor: StagePalette.band,
                showPlayLine: false,
                lineRatio: 96 / c.maxWidth,
                // Crowding notes is worse than cutting the last beats off.
                pixelsPerBeat: (usable / beats).clamp(34.0, 120.0),
                staves: fitStaves(Staves.grand, notes),
                beatsPerBar: beatsPerBar,
                keyFifths: keyFifths,
              ),
            );
          },
        ),
      ),
    );
  }
}
