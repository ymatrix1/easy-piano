import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../content/content_repo.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import '../ui/game/sfx.dart';
import 'home_page.dart' show Progress;
import '../methods/methods_library_page.dart';
import 'task_sheet.dart';

/// Learn tab: a "continue" hero card, then each section's modules on the
/// outer trail. A module card expands to show its inner trail of submodules;
/// a submodule opens a sheet with its tasks (levels).
class LearnTab extends StatefulWidget {
  const LearnTab({
    super.key,
    required this.repo,
    required this.progress,
    required this.onPlay,
    this.onOpenMethods,
  });

  final ContentRepo repo;
  final Progress progress;
  final Future<void> Function(String levelId) onPlay;
  final VoidCallback? onOpenMethods;

  @override
  State<LearnTab> createState() => _LearnTabState();
}

class _LearnTabState extends State<LearnTab> {
  late final Set<String> _open = {
    if (widget.progress.next case (final c, _)) c.id,
  };
  late final Set<String> _openSections = {
    if (widget.progress.next case (final c, _))
      c.section
    else if (widget.repo.sections.isNotEmpty)
      widget.repo.sections.first.id,
  };

  static const _tones = [GameTone.blue, GameTone.purple, GameTone.green];

  Future<void> _openNode(CourseDef course, JourneyNode node) async {
    final level = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => TaskSheet(
        repo: widget.repo,
        progress: widget.progress,
        course: course,
        node: node,
      ),
    );
    if (level != null) await widget.onPlay(level);
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final progress = widget.progress;
    final next = progress.next;
    final mainCourses = repo.courses.where((c) => !c.isMethod).toList();
    final sections = [
      ...repo.sections.where((s) => s.id != 'methods'),
      // Courses whose section is not declared still show up.
      if (mainCourses.any((c) => !repo.sections.any((s) => s.id == c.section)))
        SectionDef(id: '', title: AppLocalizations.of(context).sectionMore),
    ];
    var moduleNo = 0;

    void openMethods() {
      if (widget.onOpenMethods != null) {
        widget.onOpenMethods!();
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MethodsLibraryPage(
              repo: repo,
              progress: progress,
              onPlay: widget.onPlay,
            ),
          ),
        );
      }
    }

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
                if (repo.methods.isNotEmpty) ...[
                  _LearnModeSwitch(
                    onOpenMethods: openMethods,
                    methodCount: repo.methods.length,
                    methodStars: progress.totalMethodStars,
                  ),
                  const SizedBox(height: 18),
                ],
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
                  if (mainCourses.any((c) => c.section == section.id))
                    Builder(
                      builder: (context) {
                        final sectionCourses = mainCourses
                            .where((c) => c.section == section.id)
                            .toList();
                        final isOpen = _openSections.contains(section.id);
                        var earned = 0;
                        var total = 0;
                        for (final c in sectionCourses) {
                          earned += progress.courseStars(c);
                          total += c.nodes.length * 3;
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 20),
                            _SectionHeader(
                              title: repo.t(section.title),
                              moduleCount: sectionCourses.length,
                              earnedStars: earned,
                              totalStars: total,
                              isOpen: isOpen,
                              onToggle: () {
                                Sfx.play(SfxKind.tab);
                                setState(() {
                                  if (isOpen) {
                                    _openSections.remove(section.id);
                                  } else {
                                    _openSections.add(section.id);
                                  }
                                });
                              },
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.topCenter,
                              child: isOpen
                                  ? Padding(
                                      padding: const EdgeInsets.only(top: 14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          for (final c in sectionCourses)
                                            Builder(
                                              builder: (context) {
                                                final i = moduleNo++;
                                                final last =
                                                    c == sectionCourses.last;
                                                return SlideIn(
                                                  delay: Duration(
                                                    milliseconds:
                                                        80 +
                                                        70 * (i < 8 ? i : 8),
                                                  ),
                                                  child: _OuterTrailItem(
                                                    number: i + 1,
                                                    last: last,
                                                    state: c.planned
                                                        ? _State.locked
                                                        : progress.courseStars(
                                                                c,
                                                              ) ==
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
                                                      tone:
                                                          _tones[i %
                                                              _tones.length],
                                                      open: _open.contains(
                                                        c.id,
                                                      ),
                                                      nextNode: next?.$1 == c
                                                          ? next!.$2
                                                          : null,
                                                      onToggle: c.planned
                                                          ? null
                                                          : () => setState(
                                                              () =>
                                                                  _open
                                                                      .contains(
                                                                        c.id,
                                                                      )
                                                                  ? _open
                                                                        .remove(
                                                                          c.id,
                                                                        )
                                                                  : _open.add(
                                                                      c.id,
                                                                    ),
                                                            ),
                                                      onNode: (n) =>
                                                          _openNode(c, n),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox(width: double.infinity),
                            ),
                          ],
                        );
                      },
                    ),
                if (repo.methods.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  SlideIn(
                    delay: Duration(
                      milliseconds: 80 + 70 * (moduleNo < 8 ? moduleNo : 8),
                    ),
                    child: _MethodsCard(
                      repo: repo,
                      progress: progress,
                      onTap: openMethods,
                    ),
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

class _SectionHeader extends StatefulWidget {
  const _SectionHeader({
    required this.title,
    required this.moduleCount,
    required this.earnedStars,
    required this.totalStars,
    required this.isOpen,
    required this.onToggle,
  });

  final String title;
  final int moduleCount;
  final int earnedStars;
  final int totalStars;
  final bool isOpen;
  final VoidCallback onToggle;

  @override
  State<_SectionHeader> createState() => _SectionHeaderState();
}

class _SectionHeaderState extends State<_SectionHeader> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onToggle,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: _hover
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.03),
            border: Border.all(
              color: widget.isOpen
                  ? GameColors.yellow.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                  color: GameColors.yellow,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              GameText(widget.title, size: 20),
              const Spacer(),
              if (widget.moduleCount > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.modulesCount(widget.moduleCount).toUpperCase(),
                        style: TextStyle(
                          fontFamily: displayFont,
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '·',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFFFD54F),
                        size: 14,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${widget.earnedStars}/${widget.totalStars}',
                        style: const TextStyle(
                          fontFamily: 'Audiowide',
                          fontSize: 10,
                          color: Color(0xFFFFD54F),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
              ],
              AnimatedRotation(
                turns: widget.isOpen ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white70,
                  size: 26,
                ),
              ),
            ],
          ),
        ),
      ),
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

class _MethodsCard extends StatefulWidget {
  const _MethodsCard({
    required this.repo,
    required this.progress,
    required this.onTap,
  });

  final ContentRepo repo;
  final Progress progress;
  final VoidCallback onTap;

  @override
  State<_MethodsCard> createState() => _MethodsCardState();
}

class _MethodsCardState extends State<_MethodsCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final count = widget.repo.methods.length;
    final stars = widget.progress.totalMethodStars;
    final maxStars = widget.progress.totalMethodMaxStars;

    return Semantics(
      button: true,
      label: l10n.methodsCardTitle,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
            decoration: ShapeDecoration(
              shape: chamfer(
                20,
                side: BorderSide(
                  color: _hover
                      ? GameColors.cyan.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.16),
                  width: 1.2,
                ),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _hover ? const Color(0xFF382A7C) : const Color(0xFF2A1F5D),
                  const Color(0xFF1E1442),
                  const Color(0xFF140D30),
                ],
              ),
              shadows: [
                BoxShadow(
                  color: _hover
                      ? const Color(0xFF7B3CFF).withValues(alpha: 0.4)
                      : const Color(0xFF7B3CFF).withValues(alpha: 0.25),
                  blurRadius: _hover ? 28 : 24,
                  offset: Offset(0, _hover ? 5 : 8),
                ),
              ],
            ),
            child: ClipPath(
              clipper: ShapeBorderClipper(shape: chamfer(20)),
              child: Stack(
                children: [
                  Positioned(
                    right: -10,
                    bottom: -15,
                    child: Icon(
                      Icons.menu_book_rounded,
                      size: 140,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: ShapeDecoration(
                            shape: chamfer(12),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                            ),
                          ),
                          child: const Icon(
                            Icons.menu_book_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.methodsCardTitle.toUpperCase(),
                                style: const TextStyle(
                                  fontFamily: 'Audiowide',
                                  fontSize: 17,
                                  color: Colors.white,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.methodsCardSubtitle(count),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Color(0xFFFFD54F),
                              size: 22,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              maxStars > 0 ? '$stars / $maxStars' : '$stars',
                              style: const TextStyle(
                                fontFamily: 'Audiowide',
                                fontSize: 14,
                                color: Color(0xFFFFD54F),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LearnModeSwitch extends StatelessWidget {
  const _LearnModeSwitch({
    required this.onOpenMethods,
    required this.methodCount,
    required this.methodStars,
  });

  final VoidCallback onOpenMethods;
  final int methodCount;
  final int methodStars;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Container(
        height: 46,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xFF130C36).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [Color(0xFF28E6FF), Color(0xFF0088FF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: GameColors.cyan.withValues(alpha: 0.35),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.school_rounded,
                    size: 16,
                    color: GameColors.ink,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.learnSwitchCourses,
                    style: const TextStyle(
                      fontFamily: 'Audiowide',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: GameColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            _ClickableSwitchTab(
              label: l10n.learnSwitchMethods,
              icon: Icons.auto_stories_rounded,
              badge: methodStars > 0 ? '$methodStars ⭐' : null,
              onTap: onOpenMethods,
            ),
          ],
        ),
      ),
    );
  }
}

class _ClickableSwitchTab extends StatefulWidget {
  const _ClickableSwitchTab({
    required this.label,
    required this.icon,
    required this.onTap,
    this.badge,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? badge;

  @override
  State<_ClickableSwitchTab> createState() => _ClickableSwitchTabState();
}

class _ClickableSwitchTabState extends State<_ClickableSwitchTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () {
          Sfx.play(SfxKind.tab);
          widget.onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: _hover
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: _hover ? Colors.white : GameColors.textDim,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: 'Audiowide',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: _hover ? Colors.white : GameColors.textDim,
                ),
              ),
              if (widget.badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.badge!,
                    style: const TextStyle(
                      fontFamily: 'Audiowide',
                      fontSize: 10,
                      color: Color(0xFFFFD54F),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
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
