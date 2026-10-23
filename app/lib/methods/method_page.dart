import 'package:flutter/material.dart';

import '../content/content_repo.dart';
import '../home/home_page.dart';
import '../home/task_sheet.dart';
import '../l10n/app_localizations.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import '../ui/game/sfx.dart';

/// Screen for a specific method (e.g. Mikrokosmos) with description and collapsible books.
class MethodPage extends StatefulWidget {
  const MethodPage({
    super.key,
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
  State<MethodPage> createState() => _MethodPageState();
}

class _MethodPageState extends State<MethodPage> {
  final Set<String> _openBooks = {};

  @override
  void initState() {
    super.initState();
    _initOpenBooks();
  }

  void _initOpenBooks() {
    // Open the first unfinished book, or the first book if all are finished.
    for (final bookId in widget.method.books) {
      final c = widget.repo.courses.where((c) => c.id == bookId).firstOrNull;
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

    final nextPiece = progress.nextInMethod(method);

    return Scaffold(
      backgroundColor: GameColors.bgDeep,
      body: MenuBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBar(context, repo, method),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: homeMaxWidth(context),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHeroCard(
                              context,
                              l10n,
                              repo,
                              progress,
                              method,
                              nextPiece,
                            ),
                            const SizedBox(height: 20),
                            for (final (i, bookId) in method.books.indexed) ...[
                              _buildBookSection(
                                context,
                                l10n,
                                repo,
                                progress,
                                bookId,
                                i,
                              ),
                              const SizedBox(height: 14),
                            ],
                          ],
                        ),
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
  }

  Widget _buildTopBar(
    BuildContext context,
    ContentRepo repo,
    MethodDef method,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            mouseCursor: SystemMouseCursors.click,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (method.composer.isNotEmpty)
                  Text(
                    method.composer.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'Audiowide',
                      fontSize: 11,
                      color: GameColors.cyan,
                      letterSpacing: 1.1,
                    ),
                  ),
                Text(
                  repo.t(method.title),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
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
                size: 20,
              ),
              const SizedBox(width: 4),
              Text(
                '${widget.progress.methodStars(method)}',
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
    );
  }

  Widget _buildHeroCard(
    BuildContext context,
    AppLocalizations l10n,
    ContentRepo repo,
    Progress progress,
    MethodDef method,
    (CourseDef, JourneyNode)? nextPiece,
  ) {
    final stars = progress.methodStars(method);
    final maxStars = progress.methodMaxStars(method);

    return Container(
      decoration: ShapeDecoration(
        shape: chamfer(
          20,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E1C6A), Color(0xFF1E134C), Color(0xFF130B34)],
        ),
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: chamfer(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (method.description.isNotEmpty) ...[
                Text(
                  repo.t(method.description),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    color: Color(0xFFFFD54F),
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$stars / $maxStars',
                    style: const TextStyle(
                      fontFamily: 'Audiowide',
                      fontSize: 14,
                      color: Color(0xFFFFD54F),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    l10n.methodsBookCount(method.books.length),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              if (nextPiece != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'NEXT: ',
                      style: TextStyle(
                        fontFamily: 'Audiowide',
                        fontSize: 12,
                        color: GameColors.cyan,
                        letterSpacing: 1.1,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        repo.t(nextPiece.$2.title),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                GameButton(
                  label: l10n.methodContinue,
                  icon: Icons.play_arrow_rounded,
                  tone: GameTone.gold,
                  fontSize: 16,
                  height: 48,
                  onTap: () => _openPiece(nextPiece.$1, nextPiece.$2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static const _tones = [
    GameTone.blue,
    GameTone.purple,
    GameTone.orange,
    GameTone.green,
    GameTone.cyan,
    GameTone.red,
  ];

  Widget _buildBookSection(
    BuildContext context,
    AppLocalizations l10n,
    ContentRepo repo,
    Progress progress,
    String bookId,
    int index,
  ) {
    final course = repo.courses.where((c) => c.id == bookId).firstOrNull;
    if (course == null) return const SizedBox.shrink();

    final isOpen = _openBooks.contains(bookId);
    final bookStars = progress.courseStars(course);
    final maxBookStars = course.nodes.length * 3;
    final tone = _tones[index % _tones.length];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                Sfx.play(isOpen ? SfxKind.close : SfxKind.open);
                setState(() {
                  if (isOpen) {
                    _openBooks.remove(bookId);
                  } else {
                    _openBooks.add(bookId);
                  }
                });
              },
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: ShapeDecoration(
                  shape: chamfer(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      isOpen
                          ? Color.lerp(tone.top, Colors.white, 0.08)!
                          : tone.top,
                      tone.bottom,
                    ],
                  ),
                  shadows: [
                    BoxShadow(
                      color: tone.top.withValues(alpha: isOpen ? 0.45 : 0.25),
                      blurRadius: isOpen ? 20 : 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipPath(
                  clipper: ShapeBorderClipper(shape: chamfer(16)),
                  child: Stack(
                    children: [
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
                                  Text(
                                    'BOOK ${index + 1}',
                                    style: TextStyle(
                                      fontFamily: 'Audiowide',
                                      fontSize: 11,
                                      letterSpacing: 1.1,
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  GameText(
                                    repo.t(course.title),
                                    size: 22,
                                    align: TextAlign.left,
                                  ),
                                  if (course.description.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      repo.t(course.description),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.82,
                                        ),
                                        fontSize: 13,
                                        height: 1.3,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: GameProgressBar(
                                          value: maxBookStars == 0
                                              ? 0
                                              : bookStars / maxBookStars,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      const GameStar(fill: 1, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$bookStars/$maxBookStars',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            AnimatedRotation(
                              turns: isOpen ? 0.5 : 0.0,
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
            ),
          ),
          if (isOpen) ...[
            const SizedBox(height: 8),
            Container(
              decoration: ShapeDecoration(
                shape: chamfer(
                  14,
                  side: const BorderSide(color: GameColors.panelEdge),
                ),
                color: GameColors.panel.withValues(alpha: 0.88),
              ),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (final (i, node) in course.nodes.indexed)
                    _PieceRow(
                      index: i + 1,
                      title: repo.t(node.title),
                      stars: progress.nodeStars(node),
                      first: i == 0,
                      last: i == course.nodes.length - 1,
                      accent: tone.top,
                      onTap: () => _openPiece(course, node),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PieceRow extends StatefulWidget {
  const _PieceRow({
    required this.index,
    required this.title,
    required this.stars,
    required this.first,
    required this.last,
    required this.accent,
    required this.onTap,
  });

  final int index;
  final String title;
  final int stars;
  final bool first;
  final bool last;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_PieceRow> createState() => _PieceRowState();
}

class _PieceRowState extends State<_PieceRow> {
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
            ],
          ),
        ),
      ),
    );
  }
}
