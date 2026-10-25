import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import 'custom_score.dart';

/// Metadata of an imported score, with the Practice button. Opened after an import.
Future<void> showScorePreview(
  BuildContext context,
  CustomScore score, {
  required VoidCallback onPlay,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final l = AppLocalizations.of(dialogContext);
      return Dialog(
        backgroundColor: Colors.transparent,
        child: GamePanel(
          title: score.title,
          maxWidth: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                score.composer,
                textAlign: TextAlign.center,
                style: const TextStyle(color: GameColors.textDim, fontSize: 16),
              ),
              const SizedBox(height: 14),
              Text(
                '${l.scoreBars(score.bars)}  ·  ${l.scoreTimeSignature(score.timeSignature)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: GameColors.text, fontSize: 15),
              ),
              const SizedBox(height: 22),
              Center(
                child: GameButton(
                  label: l.scorePractice,
                  icon: Icons.play_arrow_rounded,
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    onPlay();
                  },
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l.cancel),
              ),
            ],
          ),
        ),
      );
    },
  );
}
