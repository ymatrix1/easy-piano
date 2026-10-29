import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import '../ui/staff/key_signature.dart';
import '../ui/staff/staff_note.dart';
import 'custom_score.dart';
import 'game_dialog.dart';
import 'score_info.dart';
import 'score_staff_strip.dart';
import 'score_text.dart';

/// Bars drawn in the preview.
const previewBars = 2;

/// An imported score before practice: its first bars on a staff, key, tempo, meter,
/// hands and estimated level, and a Practice button. Opened after an import.
Future<void> showScorePreview(
  BuildContext context,
  CustomScore score, {
  required List<StaffNote> notes,
  required VoidCallback onPlay,
}) {
  return showGameDialog<void>(
    context,
    builder: (dialogContext) => ScorePreviewCard(
      score: score,
      notes: notes,
      onPlay: () {
        Navigator.of(dialogContext).pop();
        onPlay();
      },
      onClose: () => Navigator.of(dialogContext).pop(),
    ),
  );
}

class ScorePreviewCard extends StatelessWidget {
  const ScorePreviewCard({
    super.key,
    required this.score,
    required this.notes,
    required this.onPlay,
    required this.onClose,
  });

  final CustomScore score;
  final List<StaffNote> notes;
  final VoidCallback onPlay;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final info = ScoreInfo.fromSongJson(score.songJson);
    final beatsPerBar = double.parse(info.timeSignature.split('/').first);
    final shownBars = info.bars < previewBars ? info.bars : previewBars;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          score.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: GameColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          score.composer,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: GameColors.textDim, fontSize: 15),
        ),
        const SizedBox(height: 14),
        if (notes.isNotEmpty) ...[
          ScoreStaffStrip(
            key: const ValueKey('score-staff-strip'),
            notes: notes,
            beats: shownBars * beatsPerBar,
            beatsPerBar: beatsPerBar,
            keyFifths: KeySignatureLayout.parseKey(info.key),
          ),
          const SizedBox(height: 14),
        ],
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(l.scoreKey(info.key)),
            _Chip(l.scoreTempo(info.bpm)),
            _Chip(l.scoreTimeSignature(info.timeSignature)),
            _Chip(l.scoreBars(info.bars)),
            _Chip(scoreHandsText(l, info)),
            _Chip(
              '${l.scoreLevelLabel}: ${scoreLevelText(l, info.level)}',
              highlight: true,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          l.scoreRightsNotice,
          textAlign: TextAlign.center,
          style: const TextStyle(color: GameColors.textDim, fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            TextButton(
              onPressed: onClose,
              child: Text(
                l.scoreClose,
                style: const TextStyle(
                  color: GameColors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            GameButton(
              label: l.scorePractice,
              icon: Icons.play_arrow_rounded,
              onTap: onPlay,
              minWidth: 140,
            ),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.highlight = false});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlight
            ? GameColors.gold.withValues(alpha: 0.18)
            : GameColors.panelHi,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight ? GameColors.gold : GameColors.panelEdge,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          text,
          style: TextStyle(
            color: highlight ? GameColors.goldLight : GameColors.text,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
