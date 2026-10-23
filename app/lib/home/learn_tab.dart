import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../content/content_repo.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import '../ui/game/sfx.dart';
import 'home_page.dart' show Progress;

/// Learn tab: a "continue" hero card, then each section's modules on the
/// outer trail. A module card expands to show its inner trail of submodules;
/// a submodule opens a sheet with its tasks (levels).
class LearnTab extends StatefulWidget {
  const LearnTab({
    super.key,
    required this.repo,
    required this.progress,
    required this.onPlay,
  });

  final ContentRepo repo;
  final Progress progress;
  final Future<void> Function(String levelId, [int initialStageIndex]) onPlay;

  @override
  State<LearnTab> createState() => _LearnTabState();
}

class _LearnTabState extends State<LearnTab> {
  late final Set<String> _open = {
    if (widget.progress.next case (final c, _)) c.id,
  };

  static const _tones = [GameTone.blue, GameTone.purple, GameTone.green];

  Future<void> _openNode(CourseDef course, JourneyNode node) async {
    final selection = await showModalBottomSheet<(String, int)>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TaskSheet(
        repo: widget.repo,
        progress: widget.progress,
        course: course,
        node: node,
      ),
    );
    if (selection != null) {
      await widget.onPlay(selection.$1, selection.$2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final progress = widget.progress;
    final next = progress.next;
    final sections = [
      ...repo.sections,
      // Courses whose section is not declared still show up.
      if (repo.courses.any((c) => !repo.sections.any((s) => s.id == c.section)))
        SectionDef(id: '', title: AppLocalizations.of(context).sectionMore),
    ];
    var moduleNo = 0;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        8 + MediaQuery.paddingOf(context).top,
        16,
        32,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: homeMaxWidth(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (next != null)
                  SlideIn(
                    child: _ContinueCard(
                      module: repo.t(next.$1.title),
                      title: repo.t(next.$2.title),
                      onPlay: () =>
                          widget.onPlay(progress.firstOpenLevel(next.$2)),
                    ),
                  ),
                for (final section in sections)
                  if (repo.courses.any((c) => c.section == section.id)) ...[
                    const SizedBox(height: 26),
                    _SectionHeader(repo.t(section.title)),
                    const SizedBox(height: 14),
                    for (final c in repo.courses.where(
                      (c) => c.section == section.id,
                    ))
                      Builder(
                        builder: (context) {
                          final i = moduleNo++;
                          final last =
                              c ==
                              repo.courses
                                  .where((x) => x.section == section.id)
                                  .last;
                          return SlideIn(
                            // Cap the stagger: with 30 modules the last
                            // would wait over two seconds.
                            delay: Duration(
                              milliseconds: 80 + 70 * (i < 8 ? i : 8),
                            ),
                            child: _OuterTrailItem(
                              number: i + 1,
                              last: last,
                              state: c.planned
                                  ? _State.locked
                                  : progress.courseStars(c) ==
                                        c.nodes.length * 3
                                  ? _State.done
                                  : next?.$1 == c
                                  ? _State.current
                                  : _State.open,
                              child: _ModuleCard(
                                repo: repo,
                                progress: progress,
                                course: c,
                                number: i + 1,
                                tone: _tones[i % _tones.length],
                                open: _open.contains(c.id),
                                nextNode: next?.$1 == c ? next!.$2 : null,
                                onToggle: c.planned
                                    ? null
                                    : () => setState(
                                        () => _open.contains(c.id)
                                            ? _open.remove(c.id)
                                            : _open.add(c.id),
                                      ),
                                onNode: (n) => _openNode(c, n),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _State { done, current, open, locked }

/// Big banner for the next submodule with a PLAY button.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.module,
    required this.title,
    required this.onPlay,
  });

  final String module;
  final String title;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return ShineSweep(
      shape: chamfer(22),
      opacity: 0.16,
      period: const Duration(milliseconds: 5200),
      child: _card(context),
    );
  }

  Widget _card(BuildContext context) {
    return Container(
      decoration: ShapeDecoration(
        shape: chamfer(
          22,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7B3CFF), Color(0xFF3A1CB8), Color(0xFF1C49D8)],
        ),
        shadows: [
          BoxShadow(
            color: const Color(0xFF7B3CFF).withValues(alpha: 0.45),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: chamfer(22)),
        child: Stack(
          children: [
            // Decorative oversized note glyph.
            Positioned(
              right: -18,
              top: -30,
              child: Icon(
                Icons.music_note_rounded,
                size: 190,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Kicker(
                    AppLocalizations.of(context).kickerContinue,
                    color: GameColors.cyan,
                  ),
                  const SizedBox(height: 8),
                  GameText(title, size: 30, align: TextAlign.left, maxLines: 2),
                  const SizedBox(height: 4),
                  Text(
                    module,
                    style: const TextStyle(
                      color: GameColors.textDim,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Bob(
                    child: GameButton(
                      label: AppLocalizations.of(context).play,
                      icon: Icons.play_arrow_rounded,
                      onTap: onPlay,
                      fontSize: 20,
                      minWidth: 170,
                      height: 54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Kicker extends StatelessWidget {
  const _Kicker(this.text, {this.color = GameColors.textDim});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontFamily: displayFont,
      color: color,
      fontSize: 11,
      letterSpacing: 1.6,
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 4, height: 22, color: GameColors.yellow),
        const SizedBox(width: 10),
        GameText(title, size: 22),
        const SizedBox(width: 14),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  GameColors.panelEdge,
                  GameColors.panelEdge.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One stop on the outer trail: numbered marker and connector on the left,
/// the module card on the right.
class _OuterTrailItem extends StatelessWidget {
  const _OuterTrailItem({
    required this.number,
    required this.last,
    required this.state,
    required this.child,
  });

  final int number;
  final bool last;
  final _State state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final (Color fill, Color fg) = switch (state) {
      _State.done => (GameColors.success, GameColors.ink),
      _State.current => (GameColors.yellow, GameColors.ink),
      _State.open => (GameColors.panelHi, Colors.white),
      _State.locked => (const Color(0xFF2A2850), const Color(0xFF8A87B8)),
    };
    Widget marker = Container(
      width: 40,
      height: 40,
      decoration: ShapeDecoration(
        shape: chamfer(
          10,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        ),
        color: fill,
      ),
      alignment: Alignment.center,
      child: state == _State.done
          ? Icon(Icons.check_rounded, color: fg, size: 24)
          : state == _State.locked
          ? Icon(Icons.lock_rounded, color: fg, size: 18)
          : GameText('$number', size: 18, color: fg, shadow: false),
    );
    if (state == _State.current) marker = Bob(child: marker);
    // Stack, not IntrinsicHeight: the card animates its height when it
    // expands, and the rail must follow every frame.
    return Stack(
      children: [
        if (!last)
          Positioned(
            left: 18,
            top: 58,
            bottom: 4,
            width: 4,
            child: _FlowRail(
              color: state == _State.locked ? const Color(0xFF2A2850) : fill,
              flowing: state == _State.current || state == _State.done,
            ),
          ),
        Positioned(left: 0, top: 14, child: marker),
        Padding(
          padding: EdgeInsets.only(left: 54, bottom: last ? 0 : 16),
          child: child,
        ),
      ],
    );
  }
}

/// Module card: header (number, title, description, progress) that toggles
/// the inner trail of submodules.
class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.repo,
    required this.progress,
    required this.course,
    required this.number,
    required this.tone,
    required this.open,
    required this.nextNode,
    required this.onToggle,
    required this.onNode,
  });

  final ContentRepo repo;
  final Progress progress;
  final CourseDef course;
  final int number;
  final GameTone tone;
  final bool open;
  final JourneyNode? nextNode;
  final VoidCallback? onToggle;
  final void Function(JourneyNode) onNode;

  @override
  Widget build(BuildContext context) {
    final locked = course.planned;
    final t = locked ? GameTone.grey : tone;
    final earned = progress.courseStars(course);
    final total = course.nodes.length * 3;
    final header = Pressable(
      onTap: onToggle,
      semanticLabel: repo.t(course.title),
      sound: open ? SfxKind.close : SfxKind.open,
      lift: 3,
      burstColor: t.top,
      onDisabledTap: locked ? () {} : null,
      builder: (p, hover) => Container(
        decoration: ShapeDecoration(
          shape: chamfer(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              hover ? Color.lerp(t.top, Colors.white, 0.08)! : t.top,
              t.bottom,
            ],
          ),
        ),
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: chamfer(16)),
          child: Stack(
            children: [
              // Diagonal sheen.
              Positioned(
                right: 40,
                top: -40,
                bottom: -40,
                width: 46,
                child: Transform.rotate(
                  angle: 0.35,
                  child: ColoredBox(
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Kicker(
                            locked
                                ? AppLocalizations.of(context).comingSoon
                                : AppLocalizations.of(context)
                                      .moduleNumber(number),
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                          const SizedBox(height: 4),
                          GameText(
                            repo.t(course.title),
                            size: 24,
                            align: TextAlign.left,
                            color: locked ? t.label : Colors.white,
                            shadow: !locked,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            repo.t(course.description),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(
                                alpha: locked ? 0.45 : 0.82,
                              ),
                              fontSize: 13.5,
                              height: 1.3,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (!locked) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: GameProgressBar(
                                    value: total == 0 ? 0 : earned / total,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const GameStar(fill: 1, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  '$earned/$total',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!locked)
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 240),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: open && !locked
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _InnerTrail(
                    repo: repo,
                    progress: progress,
                    nodes: course.nodes,
                    next: nextNode,
                    accent: tone.top,
                    onNode: onNode,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Submodules of one module, joined by a thin rail.
class _InnerTrail extends StatelessWidget {
  const _InnerTrail({
    required this.repo,
    required this.progress,
    required this.nodes,
    required this.next,
    required this.accent,
    required this.onNode,
  });

  final ContentRepo repo;
  final Progress progress;
  final List<JourneyNode> nodes;
  final JourneyNode? next;
  final Color accent;
  final void Function(JourneyNode) onNode;

  static IconData _icon(String kind) => switch (kind) {
    'song' => Icons.music_note_rounded,
    'boss' || 'mini_boss' => Icons.emoji_events_rounded,
    'star_gate' => Icons.star_rounded,
    _ => Icons.school_rounded,
  };

  static String _kind(AppLocalizations l, String kind) => switch (kind) {
    'song' => l.kindSong,
    'boss' => l.kindBoss,
    'mini_boss' => l.kindChallenge,
    'star_gate' => l.kindStarGate,
    _ => l.kindLesson,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: ShapeDecoration(
        shape: chamfer(14, side: const BorderSide(color: GameColors.panelEdge)),
        color: GameColors.panel.withValues(alpha: 0.88),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final (i, n) in nodes.indexed)
            SlideIn(
              delay: Duration(milliseconds: 40 * i),
              offset: const Offset(-18, 0),
              child: _SubmoduleRow(
                index: i + 1,
                title: repo.t(n.title),
                kind: _kind(AppLocalizations.of(context), n.kind),
                icon: _icon(n.kind),
                tasks: n.levels.length,
                stars: progress.nodeStars(n),
                isNext: n == next,
                first: i == 0,
                last: i == nodes.length - 1,
                accent: accent,
                onTap: () => onNode(n),
              ),
            ),
        ],
      ),
    );
  }
}

class _SubmoduleRow extends StatelessWidget {
  const _SubmoduleRow({
    required this.index,
    required this.title,
    required this.kind,
    required this.icon,
    required this.tasks,
    required this.stars,
    required this.isNext,
    required this.first,
    required this.last,
    required this.accent,
    required this.onTap,
  });

  final int index;
  final String title;
  final String kind;
  final IconData icon;
  final int tasks;
  final int stars;
  final bool isNext;
  final bool first;
  final bool last;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = stars > 0;
    final nodeColor = done
        ? GameColors.success
        : isNext
        ? GameColors.yellow
        : GameColors.panelHi;
    Widget node = Container(
      width: 36,
      height: 36,
      decoration: ShapeDecoration(
        shape: chamfer(
          9,
          side: BorderSide(
            color: done || isNext
                ? Colors.white.withValues(alpha: 0.35)
                : GameColors.panelEdge,
          ),
        ),
        color: nodeColor,
      ),
      child: Icon(
        done ? Icons.check_rounded : icon,
        size: 20,
        color: done || isNext ? GameColors.ink : Colors.white,
      ),
    );
    if (isNext) node = Bob(child: node);
    final rail = Container(width: 2, color: GameColors.panelEdge);
    return Pressable(
      onTap: onTap,
      semanticLabel: title,
      burstColor: GameColors.cyan,
      // Hover never changes layout (the rail must stay continuous): a wash
      // in the module colour fades in, the node grows, the chevron slides.
      builder: (p, hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: hover ? 0.22 : 0),
              accent.withValues(alpha: hover ? 0.04 : 0),
            ],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: IntrinsicHeight(
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Column(
                  children: [
                    Expanded(child: first ? const SizedBox() : rail),
                    AnimatedScale(
                      scale: hover ? 1.12 : 1,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutBack,
                      child: node,
                    ),
                    Expanded(child: last ? const SizedBox() : rail),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${kind.toUpperCase()}  ·  ${AppLocalizations.of(context).taskCount(tasks).toUpperCase()}',
                        style: TextStyle(
                          fontFamily: displayFont,
                          color: accent,
                          fontSize: 10,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$index. $title',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var s = 0; s < 3; s++)
                    GameStar(fill: s < stars ? 1 : 0, size: 16),
                ],
              ),
              const SizedBox(width: 10),
              if (isNext)
                GameButton(
                  label: AppLocalizations.of(context).play,
                  onTap: onTap,
                  fontSize: 14,
                  minWidth: 0,
                  height: 36,
                )
              else
                AnimatedSlide(
                  offset: Offset(hover ? 0.25 : 0, 0),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: hover
                        ? GameColors.yellow
                        : Colors.white.withValues(alpha: 0.4),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet listing a submodule's tasks; returns the level id to play.
class _TaskSheet extends StatelessWidget {
  const _TaskSheet({
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
    final targetLevel = repo.levels[open];
    final stages = targetLevel?.stages ?? const [];
    final hasWait = stages.any((s) => s.type == 'wait');
    final playAlongIndex = stages.indexWhere((s) => s.type == 'play_along');
    final hasBoth = hasWait && playAlongIndex >= 0;

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
                    _Kicker(repo.t(course.title), color: GameColors.cyan),
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
                          onTap: () => Navigator.of(context).pop((id, 0)),
                        ),
                      ),
                    const SizedBox(height: 10),
                    if (hasBoth)
                      Row(
                        children: [
                          Expanded(
                            child: GameButton(
                              label: AppLocalizations.of(context).navPractice,
                              icon: Icons.fitness_center_rounded,
                              tone: GameTone.purple,
                              onTap: () => Navigator.of(context).pop((open, 0)),
                              fontSize: 17,
                              height: 54,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GameButton(
                              label: AppLocalizations.of(context)
                                  .practicePlayAlong,
                              icon: Icons.play_arrow_rounded,
                              onTap: () =>
                                  Navigator.of(context)
                                      .pop((open, playAlongIndex)),
                              fontSize: 17,
                              height: 54,
                            ),
                          ),
                        ],
                      )
                    else
                      GameButton(
                        label: AppLocalizations.of(context).play,
                        icon: Icons.play_arrow_rounded,
                        onTap: () => Navigator.of(context).pop((open, 0)),
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

/// Outer-trail connector; on the active part, light pulses flow downward.
class _FlowRail extends StatefulWidget {
  const _FlowRail({required this.color, required this.flowing});

  final Color color;
  final bool flowing;

  @override
  State<_FlowRail> createState() => _FlowRailState();
}

class _FlowRailState extends State<_FlowRail>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.flowing && !reduceMotion(context) && !_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _FlowPainter(_c, widget.color, widget.flowing));
}

class _FlowPainter extends CustomPainter {
  _FlowPainter(this.anim, this.color, this.flowing) : super(repaint: anim);

  final Animation<double> anim;
  final Color color;
  final bool flowing;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width / 2),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, GameColors.panelEdge.withValues(alpha: 0.5)],
        ).createShader(r.outerRect),
    );
    if (!flowing) return;
    canvas.save();
    canvas.clipRRect(r);
    const pulse = 46.0;
    for (var k = 0; k < 3; k++) {
      final y = ((anim.value + k / 3) % 1.0) * (size.height + pulse) - pulse;
      final rect = Rect.fromLTWH(0, y, size.width, pulse);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.85),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlowPainter old) =>
      old.color != color || old.flowing != flowing;
}
