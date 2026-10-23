import 'package:flutter/material.dart';

import '../content/content_repo.dart';
import '../l10n/app_localizations.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import 'home_page.dart' show Progress;

/// Bottom sheet listing a submodule's tasks; returns the level id to play.
class TaskSheet extends StatelessWidget {
  const TaskSheet({
    super.key,
    required this.repo,
    required this.progress,
    required this.course,
    required this.node,
  });

  final ContentRepo repo;
  final Progress progress;
  final CourseDef course;
  final JourneyNode node;

  @override
  Widget build(BuildContext context) {
    final open = progress.firstOpenLevel(node);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: PopIn(
              from: 0.94,
              child: GamePanel(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      repo.t(course.title).toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Audiowide',
                        fontSize: 12,
                        letterSpacing: 1.2,
                        color: GameColors.cyan,
                      ),
                    ),
                    const SizedBox(height: 6),
                    GameText(
                      repo.t(node.title),
                      size: 26,
                      align: TextAlign.left,
                    ),
                    if (node.starsNeeded case final need?) ...[
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context).gateProgress(
                          need,
                          progress.gateStars(node).clamp(0, need),
                        ),
                        style: const TextStyle(color: GameColors.textDim),
                      ),
                    ],
                    const SizedBox(height: 16),
                    for (final (i, id) in node.levels.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _TaskRow(
                          index: i + 1,
                          title: repo.t(repo.levels[id]?.title ?? id),
                          stars: progress.levelStars[id] ?? 0,
                          isNext: id == open,
                          onTap: () => Navigator.of(context).pop(id),
                        ),
                      ),
                    const SizedBox(height: 10),
                    GameButton(
                      label: AppLocalizations.of(context).play,
                      icon: Icons.play_arrow_rounded,
                      onTap: () => Navigator.of(context).pop(open),
                      fontSize: 20,
                      height: 54,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.index,
    required this.title,
    required this.stars,
    required this.isNext,
    required this.onTap,
  });

  final int index;
  final String title;
  final int stars;
  final bool isNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: title,
      builder: (p, hover) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: ShapeDecoration(
          shape: chamfer(
            10,
            side: BorderSide(
              color: isNext ? GameColors.yellow : GameColors.panelEdge,
            ),
          ),
          color: Colors.black.withValues(alpha: hover ? 0.2 : 0.28),
        ),
        child: Row(
          children: [
            GameText(
              '$index',
              size: 18,
              color: isNext ? GameColors.yellow : GameColors.textDim,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
            for (var s = 0; s < 3; s++)
              GameStar(fill: s < stars ? 1 : 0, size: 18),
          ],
        ),
      ),
    );
  }
}
