import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import 'custom_score_controller.dart';
import 'game_dialog.dart';
import 'score_text.dart';

/// Whether [outcome] needs this summary. A single imported score with no failures
/// goes straight to its preview instead.
bool needsImportSummary(ImportOutcome outcome) =>
    outcome.failures.isNotEmpty || outcome.imported.length > 1;

/// What happened to each file of an import: the scores added and, for each file that
/// was not, why and what to do. Returns true when the player asks for the library.
Future<bool> showImportResults(
  BuildContext context,
  ImportOutcome outcome,
) async {
  final open = await showGameDialog<bool>(
    context,
    builder: (dialogContext) => ImportResultsCard(
      outcome: outcome,
      onOpenLibrary: () => Navigator.of(dialogContext).pop(true),
      onClose: () => Navigator.of(dialogContext).pop(false),
    ),
  );
  return open ?? false;
}

class ImportResultsCard extends StatelessWidget {
  const ImportResultsCard({
    super.key,
    required this.outcome,
    required this.onOpenLibrary,
    required this.onClose,
  });

  final ImportOutcome outcome;
  final VoidCallback onOpenLibrary;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GameText(l.importResultsTitle, size: 22),
        const SizedBox(height: 14),
        if (outcome.imported.isNotEmpty) ...[
          _Heading(
            icon: Icons.check_circle_rounded,
            color: GameColors.success,
            text: l.importAdded(outcome.imported.length),
          ),
          for (final s in outcome.imported)
            _Line(title: s.title, detail: s.fileName),
          const SizedBox(height: 12),
        ],
        if (outcome.failures.isNotEmpty) ...[
          _Heading(
            icon: Icons.error_rounded,
            color: GameColors.danger,
            text: l.importNotAdded,
          ),
          for (final f in outcome.failures)
            _Line(title: f.fileName, detail: importProblemText(l, f.problem)),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
        if (outcome.imported.isNotEmpty)
          Center(
            child: GameButton(label: l.scoreOpenLibrary, onTap: onOpenLibrary),
          ),
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
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: GameColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: GameColors.text,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            detail,
            style: const TextStyle(color: GameColors.textDim, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}
