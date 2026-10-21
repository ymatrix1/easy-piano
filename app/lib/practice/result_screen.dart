import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../src/rust/api/practice.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';

/// End-of-stage result: title banner, stars, stat medallions, retry / next.
/// See docs/specs/practice-screen.md and docs/specs/visual-style.md.
class ResultScreen extends StatelessWidget {
  const ResultScreen({
    super.key,
    required this.result,
    required this.stageType,
    required this.songTitle,
    required this.onRetry,
    required this.onNext,
  });

  final ResultView result;
  final String stageType;
  final String songTitle;
  final VoidCallback onRetry;
  final VoidCallback onNext;

  /// Round medallion with a count-up value and a progress ring.
  Widget _stat(
    IconData icon,
    String label,
    double value,
    String Function(double) format,
    double fraction,
    int order,
  ) {
    final delay = Duration(milliseconds: 900 + 150 * order);
    return PopIn(
      delay: delay,
      child: Column(
        children: [
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: GameColors.panel,
              border: Border.all(color: GameColors.panelEdge, width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 8,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            padding: const EdgeInsets.all(7),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => CircularProgressIndicator(
                      value: v,
                      strokeWidth: 5,
                      strokeCap: StrokeCap.round,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(GameColors.yellow),
                    ),
                  ),
                ),
                // Inner padding keeps the value clear of the ring.
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: GameColors.yellow, size: 20),
                      const SizedBox(height: 4),
                      FittedBox(
                        child: CountUp(
                          value: value,
                          format: format,
                          size: 16,
                          delay: delay,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          GameText(label, size: 13, color: GameColors.textDim),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = result;
    // Reference formulas live in the core (session.rs): notes hit/total,
    // timing from the mean and spread of errors, assists = tempo used.
    final playAlong = stageType == 'play_along';
    final notesFrac = r.notesTotal == 0 ? 0.0 : r.notesHit / r.notesTotal;
    final title = songTitle;
    String pct(double v) => '${v.round()}%';
    final l = AppLocalizations.of(context);
    final rule = playAlong
        ? l.passRulePlayAlong((r.threshold * 100).round())
        : stageType == 'one_note'
        ? l.passRuleOneNote
        : l.passRuleWait;
    final hint = r.suggestPractice ? '$rule ${l.trySlowerTempo}' : rule;
    return ResultBackground(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopIn(
                child: GameRibbon(
                  r.passed
                      ? AppLocalizations.of(context).completed
                      : AppLocalizations.of(context).almostThere,
                  tone: r.passed ? GameTone.green : GameTone.red,
                  fontSize: 36,
                ),
              ),
              if (title.isNotEmpty)
                SlideIn(
                  delay: const Duration(milliseconds: 150),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: GameText(title, size: 20, color: GameColors.cyan),
                  ),
                ),
              const SizedBox(height: 12),
              // Stars fill continuously (e.g. half a star), as in the reference.
              StarRow(
                stars: r.starsExact,
                delay: const Duration(milliseconds: 300),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 28,
                runSpacing: 12,
                children: [
                  _stat(
                    Icons.music_note_rounded,
                    AppLocalizations.of(context).statNotes.toUpperCase(),
                    r.notesHit.toDouble(),
                    (v) => '${v.round()}/${r.notesTotal}',
                    notesFrac,
                    0,
                  ),
                  if (playAlong) ...[
                    _stat(
                      Icons.timer_rounded,
                      AppLocalizations.of(context).statTiming.toUpperCase(),
                      r.timing * 100,
                      pct,
                      r.timing,
                      1,
                    ),
                    _stat(
                      Icons.support_rounded,
                      AppLocalizations.of(context).statAssists.toUpperCase(),
                      r.assists * 100,
                      pct,
                      r.assists,
                      2,
                    ),
                  ],
                ],
              ),
              if (!r.passed)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              SlideIn(
                delay: const Duration(milliseconds: 1300),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Same height and edge so the pair reads as one group.
                    GameRoundButton(
                      icon: Icons.replay_rounded,
                      onTap: onRetry,
                      tone: GameTone.blue,
                      size: 58,
                      tooltip: AppLocalizations.of(context).retry,
                    ),
                    const SizedBox(width: 14),
                    GameButton(
                      label: r.passed
                          ? AppLocalizations.of(context).next
                          : AppLocalizations.of(context).locked,
                      icon: r.passed ? null : Icons.lock_rounded,
                      trailingIcon: r.passed
                          ? Icons.arrow_forward_rounded
                          : null,
                      onTap: r.passed ? onNext : null,
                      tone: GameTone.green,
                      fontSize: 20,
                      height: 58,
                      minWidth: 180,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
