import 'package:flutter/material.dart';

import '../content/content_repo.dart';
import '../home/home_page.dart';
import '../home/task_sheet.dart';
import '../l10n/app_localizations.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import '../ui/game/sfx.dart';

/// Methods library screen: browsable catalog of piano methods outside the main course.
class MethodsLibraryPage extends StatelessWidget {
  const MethodsLibraryPage({
    super.key,
    required this.repo,
    required this.progress,
    required this.onPlay,
  });

  final ContentRepo repo;
  final Progress progress;
  final Future<void> Function(String levelId, [int initialStageIndex]) onPlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: GameColors.bgDeep,
      body: MenuBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                      mouseCursor: SystemMouseCursors.click,
                      tooltip: MaterialLocalizations.of(context)
                          .backButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.methodsLibraryTitle.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Audiowide',
                        fontSize: 20,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFD54F),
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${progress.totalMethodStars}',
                          style: const TextStyle(
                            fontFamily: 'Audiowide',
                            fontSize: 15,
                            color: Color(0xFFFFD54F),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: MethodsCatalogView(
                  repo: repo,
                  progress: progress,
                  onPlay: onPlay,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Catalog view of methods with filter chips and method cards.
/// Can be embedded inline in the Learn tab or shown in [MethodsLibraryPage].
class MethodsCatalogView extends StatefulWidget {
  const MethodsCatalogView({
    super.key,
    required this.repo,
    required this.progress,
    required this.onPlay,
    this.embedded = false,
  });

  final ContentRepo repo;
  final Progress progress;
  final Future<void> Function(String levelId, [int initialStageIndex]) onPlay;
  final bool embedded;

  @override
  State<MethodsCatalogView> createState() => _MethodsCatalogViewState();
}

class _MethodsCatalogViewState extends State<MethodsCatalogView> {
  String? _selectedLevel;
  String? _selectedSkill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = widget.repo;
    final progress = widget.progress;

    final filteredMethods = repo.methods.where((m) {
      if (_selectedLevel != null && !m.levels.contains(_selectedLevel)) {
        return false;
      }
      if (_selectedSkill != null && !m.skills.contains(_selectedSkill)) {
        return false;
      }
      return true;
    }).toList();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilterChips(context, l10n),
        const SizedBox(height: 18),
        for (final (i, method) in filteredMethods.indexed)
          SlideIn(
            delay: Duration(milliseconds: 60 + 60 * i),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _MethodCard(
                repo: repo,
                progress: progress,
                method: method,
                onPlay: widget.onPlay,
              ),
            ),
          ),
        if (filteredMethods.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                l10n.methodsFilterAll,
                style: const TextStyle(color: GameColors.textDim, fontSize: 16),
              ),
            ),
          ),
      ],
    );

    if (widget.embedded) return content;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: homeMaxWidth(context)),
            child: content,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips(BuildContext context, AppLocalizations l10n) {
    final levelLabels = <String, String>{
      'beginner': l10n.methodsFilterBeginner,
      'early-intermediate': l10n.methodsFilterEarlyIntermediate,
      'intermediate': l10n.methodsFilterIntermediate,
    };

    final skillLabels = <String, String>{
      'reading': l10n.methodsFilterReading,
      'rhythm': l10n.methodsFilterRhythm,
      'independence': l10n.methodsFilterIndependence,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ShapeDecoration(
        color: const Color(0xFF140D36).withValues(alpha: 0.85),
        shape: chamfer(
          14,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: ShapeDecoration(
                  color: GameColors.cyan.withValues(alpha: 0.15),
                  shape: chamfer(
                    6,
                    side: BorderSide(
                      color: GameColors.cyan.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: const Text(
                  'LEVEL',
                  style: TextStyle(
                    fontFamily: 'Audiowide',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: GameColors.cyan,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: l10n.methodsFilterAll,
                        selected: _selectedLevel == null,
                        onTap: () {
                          Sfx.play(SfxKind.tab);
                          setState(() => _selectedLevel = null);
                        },
                      ),
                      const SizedBox(width: 8),
                      for (final entry in levelLabels.entries) ...[
                        _FilterChip(
                          label: entry.value,
                          selected: _selectedLevel == entry.key,
                          onTap: () {
                            Sfx.play(SfxKind.tab);
                            setState(() {
                              _selectedLevel = _selectedLevel == entry.key
                                  ? null
                                  : entry.key;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: ShapeDecoration(
                  color: GameColors.yellow.withValues(alpha: 0.15),
                  shape: chamfer(
                    6,
                    side: BorderSide(
                      color: GameColors.yellow.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: const Text(
                  'SKILL',
                  style: TextStyle(
                    fontFamily: 'Audiowide',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: GameColors.yellow,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: l10n.methodsFilterAll,
                        selected: _selectedSkill == null,
                        onTap: () {
                          Sfx.play(SfxKind.tab);
                          setState(() => _selectedSkill = null);
                        },
                      ),
                      const SizedBox(width: 8),
                      for (final entry in skillLabels.entries) ...[
                        _FilterChip(
                          label: entry.value,
                          selected: _selectedSkill == entry.key,
                          onTap: () {
                            Sfx.play(SfxKind.tab);
                            setState(() {
                              _selectedSkill = _selectedSkill == entry.key
                                  ? null
                                  : entry.key;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatefulWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: ShapeDecoration(
            shape: chamfer(
              8,
              side: BorderSide(
                color: selected
                    ? GameColors.cyan
                    : _hover
                    ? Colors.white38
                    : Colors.white12,
                width: selected ? 1.5 : 1,
              ),
            ),
            color: selected
                ? GameColors.cyan.withValues(alpha: 0.22)
                : _hover
                ? const Color(0xFF261D5A)
                : const Color(0xFF1B1446),
            shadows: selected
                ? [
                    BoxShadow(
                      color: GameColors.cyan.withValues(alpha: 0.3),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: selected
                  ? Colors.white
                  : (_hover ? Colors.white70 : GameColors.textDim),
            ),
          ),
        ),
      ),
    );
  }
}

class _MethodCard extends StatefulWidget {
  const _MethodCard({
    required this.repo,
    required this.progress,
    required this.method,
    required this.onPlay,
  });

  final ContentRepo repo;
  final Progress progress;
  final MethodDef method;
  final Future<void> Function(String levelId, [int initialStageIndex]) onPlay;

  @override
  State<_MethodCard> createState() => _MethodCardState();
}

class _MethodCardState extends State<_MethodCard> {
  bool _open = false;
  final Set<String> _openBooks = {};
  bool _hover = false;

  static const _tones = [
    GameTone.blue,
    GameTone.purple,
    GameTone.orange,
    GameTone.green,
    GameTone.cyan,
    GameTone.red,
  ];

  void _toggleOpen() {
    setState(() {
      _open = !_open;
      if (_open && _openBooks.isEmpty) {
        for (final bookId in widget.method.books) {
          final c = widget.repo.courses
              .where((c) => c.id == bookId)
              .firstOrNull;
          if (c == null) continue;
          final max = c.nodes.length * 3;
          if (max == 0 || widget.progress.courseStars(c) < max) {
            _openBooks.add(bookId);
            break;
          }
        }
        if (_openBooks.isEmpty && widget.method.books.isNotEmpty) {
          _openBooks.add(widget.method.books.first);
        }
      }
    });
    Sfx.play(_open ? SfxKind.open : SfxKind.close);
  }

  Future<void> _openPiece(CourseDef course, JourneyNode node) async {
    final selection = await showModalBottomSheet<(String, int)>(
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
    if (selection != null) {
      await widget.onPlay(selection.$1, selection.$2);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = widget.repo;
    final progress = widget.progress;
    final method = widget.method;

    final stars = progress.methodStars(method);
    final maxStars = progress.methodMaxStars(method);
    final ratio = maxStars > 0 ? (stars / maxStars).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: _toggleOpen,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
              decoration: ShapeDecoration(
                shape: chamfer(
                  16,
                  side: BorderSide(
                    color: _open
                        ? GameColors.cyan.withValues(alpha: 0.6)
                        : (_hover
                              ? GameColors.cyan.withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.14)),
                    width: _open ? 1.5 : 1.2,
                  ),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _open
                        ? const Color(0xFF382582)
                        : (_hover
                              ? const Color(0xFF342378)
                              : const Color(0xFF281C60)),
                    const Color(0xFF1B1245),
                    const Color(0xFF120C30),
                  ],
                ),
                shadows: [
                  BoxShadow(
                    color: (_open || _hover)
                        ? const Color(0xFF6B21A8).withValues(alpha: 0.45)
                        : Colors.black.withValues(alpha: 0.35),
                    blurRadius: (_open || _hover) ? 24 : 14,
                    offset: Offset(0, (_open || _hover) ? 6 : 3),
                  ),
                ],
              ),
              child: ClipPath(
                clipper: ShapeBorderClipper(shape: chamfer(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (method.composer.isNotEmpty) ...[
                                  Text(
                                    '${method.composer.toUpperCase()} · METHOD',
                                    style: const TextStyle(
                                      fontFamily: 'Audiowide',
                                      fontSize: 11,
                                      color: GameColors.cyan,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                GameText(
                                  repo.t(method.title),
                                  size: 26,
                                  align: TextAlign.left,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: ShapeDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              shape: chamfer(
                                6,
                                side: const BorderSide(color: Colors.white12),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.menu_book_rounded,
                                  size: 14,
                                  color: GameColors.cyan,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  l10n
                                      .methodsBookCount(method.books.length)
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    fontFamily: 'Audiowide',
                                    fontSize: 11,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (method.description.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          repo.t(method.description),
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.4,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                      if (method.skills.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final s in method.skills)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: ShapeDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  shape: chamfer(
                                    6,
                                    side: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _skillLabel(s, l10n),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 18),
                      const Divider(color: Colors.white10, height: 1),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      color: Color(0xFFFFD54F),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$stars / $maxStars',
                                      style: const TextStyle(
                                        fontFamily: 'Audiowide',
                                        fontSize: 13,
                                        color: Color(0xFFFFD54F),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                GameProgressBar(value: ratio),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          GameButton(
                            label: l10n.methodsExplore,
                            icon: _open
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.arrow_forward_rounded,
                            tone: GameTone.gold,
                            fontSize: 14,
                            minWidth: 120,
                            height: 44,
                            onTap: _toggleOpen,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, bookId) in method.books.indexed)
                        Builder(
                          builder: (context) {
                            final course = repo.courses
                                .where((c) => c.id == bookId)
                                .firstOrNull;
                            if (course == null) return const SizedBox.shrink();
                            final isBookOpen = _openBooks.contains(bookId);
                            final bookStars = progress.courseStars(course);
                            final maxBookStars = course.nodes.length * 3;
                            final tone = _tones[i % _tones.length];

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: () {
                                        Sfx.play(
                                          isBookOpen
                                              ? SfxKind.close
                                              : SfxKind.open,
                                        );
                                        setState(() {
                                          if (isBookOpen) {
                                            _openBooks.remove(bookId);
                                          } else {
                                            _openBooks.add(bookId);
                                          }
                                        });
                                      },
                                      behavior: HitTestBehavior.opaque,
                                      child: Container(
                                        decoration: ShapeDecoration(
                                          shape: chamfer(14),
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              isBookOpen
                                                  ? Color.lerp(
                                                      tone.top,
                                                      Colors.white,
                                                      0.08,
                                                    )!
                                                  : tone.top,
                                              tone.bottom,
                                            ],
                                          ),
                                          shadows: [
                                            BoxShadow(
                                              color: tone.top.withValues(
                                                alpha: isBookOpen ? 0.35 : 0.18,
                                              ),
                                              blurRadius: isBookOpen ? 16 : 8,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          14,
                                          14,
                                          14,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'BOOK ${i + 1}',
                                                    style: TextStyle(
                                                      fontFamily: 'Audiowide',
                                                      fontSize: 10,
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.75,
                                                          ),
                                                      letterSpacing: 0.8,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  GameText(
                                                    repo.t(course.title),
                                                    size: 18,
                                                    align: TextAlign.left,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    l10n.taskCount(
                                                      course.nodes.length,
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.7,
                                                          ),
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
                                                  size: 18,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '$bookStars / $maxBookStars',
                                                  style: const TextStyle(
                                                    fontFamily: 'Audiowide',
                                                    fontSize: 12.5,
                                                    color: Color(0xFFFFD54F),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                AnimatedRotation(
                                                  turns: isBookOpen ? 0.5 : 0,
                                                  duration: const Duration(
                                                    milliseconds: 220,
                                                  ),
                                                  child: const Icon(
                                                    Icons
                                                        .keyboard_arrow_down_rounded,
                                                    color: Colors.white,
                                                    size: 26,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 240),
                                    curve: Curves.easeOutCubic,
                                    alignment: Alignment.topCenter,
                                    child: isBookOpen
                                        ? Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                            ),
                                            child: Container(
                                              decoration: ShapeDecoration(
                                                shape: chamfer(
                                                  14,
                                                  side: const BorderSide(
                                                    color: GameColors.panelEdge,
                                                  ),
                                                ),
                                                color: GameColors.panel
                                                    .withValues(alpha: 0.88),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 6,
                                                  ),
                                              child: Column(
                                                children: [
                                                  for (final (j, node)
                                                      in course.nodes.indexed)
                                                    _MethodPieceRow(
                                                      index: j + 1,
                                                      title: repo.t(node.title),
                                                      stars: progress.nodeStars(
                                                        node,
                                                      ),
                                                      onTap: () => _openPiece(
                                                        course,
                                                        node,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          )
                                        : const SizedBox(
                                            width: double.infinity,
                                          ),
                                  ),
                                ],
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
  }

  String _skillLabel(String s, AppLocalizations l10n) => switch (s) {
    'reading' => l10n.methodsFilterReading,
    'rhythm' => l10n.methodsFilterRhythm,
    'independence' => l10n.methodsFilterIndependence,
    _ => s,
  };
}

class _MethodPieceRow extends StatefulWidget {
  const _MethodPieceRow({
    required this.index,
    required this.title,
    required this.stars,
    required this.onTap,
  });

  final int index;
  final String title;
  final int stars;
  final VoidCallback onTap;

  @override
  State<_MethodPieceRow> createState() => _MethodPieceRowState();
}

class _MethodPieceRowState extends State<_MethodPieceRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () {
          Sfx.play(SfxKind.tap);
          widget.onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          color: _hover
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: ShapeDecoration(
                  shape: chamfer(
                    8,
                    side: BorderSide(
                      color: _hover ? GameColors.cyan : Colors.white12,
                    ),
                  ),
                  color: widget.stars > 0
                      ? GameColors.success
                      : const Color(0xFF282054),
                ),
                alignment: Alignment.center,
                child: widget.stars > 0
                    ? const Icon(
                        Icons.check_rounded,
                        color: GameColors.ink,
                        size: 18,
                      )
                    : Text(
                        '${widget.index}',
                        style: const TextStyle(
                          fontFamily: 'Audiowide',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: _hover
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              for (var s = 0; s < 3; s++)
                GameStar(fill: s < widget.stars ? 1 : 0, size: 16),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Colors.white.withValues(alpha: _hover ? 0.9 : 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
